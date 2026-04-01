const std = @import("std");
const tea = @import("tea.zig");
const ui = @import("ui.zig");

// Same compact queue strategy as the terminal runtime, but without any host
// dependencies.
fn Queue(comptime T: type) type {
    return struct {
        items: std.ArrayList(T) = .empty,
        head: usize = 0,

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.items.deinit(allocator);
        }

        pub fn push(self: *@This(), allocator: std.mem.Allocator, value: T) !void {
            try self.items.append(allocator, value);
        }

        pub fn pop(self: *@This()) ?T {
            if (self.head >= self.items.items.len) return null;

            const value = self.items.items[self.head];
            self.head += 1;
            self.compact();
            return value;
        }

        pub fn clearRetainingCapacity(self: *@This()) void {
            self.items.clearRetainingCapacity();
            self.head = 0;
        }

        fn compact(self: *@This()) void {
            if (self.head == 0) return;

            if (self.head == self.items.items.len) {
                self.items.clearRetainingCapacity();
                self.head = 0;
                return;
            }

            if (self.head < 64 and self.head * 2 < self.items.items.len) return;

            const remaining = self.items.items.len - self.head;
            std.mem.copyForwards(
                T,
                self.items.items[0..remaining],
                self.items.items[self.head..],
            );
            self.items.items.len = remaining;
            self.head = 0;
        }
    };
}

/// Host-agnostic runtime for tests, automation, and WASM adapters.
pub fn HeadlessProgram(comptime ModelType: type, comptime UserMsg: type) type {
    comptime {
        if (!@hasDecl(ModelType, "update")) {
            @compileError("ModelType must declare update(self: *ModelType, msg: Msg) !tea.Update(Msg)");
        }
        if (!@hasDecl(ModelType, "view") and !@hasDecl(ModelType, "compose")) {
            @compileError("ModelType must declare either view(self: *const ModelType, writer: anytype) !void or compose(self: *const ModelType, tree: *ui.Tree) !ui.NodeId");
        }
    }

    const Msg = tea.Message(UserMsg);
    const Command = tea.Cmd(Msg);
    const UpdateResult = tea.Update(Msg);

    const ScheduledMessage = struct {
        deadline_ns: u64,
        msg: Msg,
    };

    const Step = enum {
        idle,
        progressed,
        quit,
    };

    return struct {
        allocator: std.mem.Allocator,
        model: ModelType,
        pending: Queue(Msg) = .{},
        scheduled: std.ArrayList(ScheduledMessage) = .empty,
        frame_buffer: std.ArrayList(u8) = .empty,
        dirty: bool = true,
        initialized: bool = false,
        quit_requested: bool = false,
        now_ns: u64 = 0,
        last_cursor: ?ui.Cursor = null,
        options: Options,

        const Self = @This();
        pub const StepStatus = Step;
        pub const Options = struct {
            /// Headless hosts still inject one initial resize so models can
            /// share the same first-update contract as terminal and WASM
            /// hosts.
            initial_size: ?tea.Size = .{},
        };

        /// Creates a deterministic runtime around a model instance.
        pub fn init(allocator: std.mem.Allocator, model: ModelType) Self {
            return initWithOptions(allocator, model, .{});
        }

        /// Creates a deterministic runtime around a model instance with an
        /// explicit host contract.
        pub fn initWithOptions(allocator: std.mem.Allocator, model: ModelType, options: Options) Self {
            return .{
                .allocator = allocator,
                .model = model,
                .options = options,
            };
        }

        /// Releases queues and frame buffers owned by the headless host.
        pub fn deinit(self: *Self) void {
            self.pending.deinit(self.allocator);
            self.scheduled.deinit(self.allocator);
            self.frame_buffer.deinit(self.allocator);
        }

        /// Runs model init exactly once, mirroring the interactive runtime.
        pub fn boot(self: *Self) !void {
            if (self.initialized or self.quit_requested) return;
            self.initialized = true;

            if (self.options.initial_size) |size| {
                try self.pending.push(self.allocator, .{ .resize = size });
            }
            if (@hasDecl(ModelType, "init")) {
                try self.dispatchCommand(self.model.init());
            }
        }

        /// Queues a message for the next `step` or `drain` call.
        pub fn send(self: *Self, msg: Msg) !void {
            if (self.quit_requested) return error.ProgramExited;
            try self.pending.push(self.allocator, msg);
        }

        /// Advances time by a delta and drains all resulting work.
        pub fn advanceBy(self: *Self, delta_ns: u64) !bool {
            if (self.quit_requested) return true;
            self.now_ns += delta_ns;
            return self.drain();
        }

        /// Moves the clock to an absolute timestamp and drains due work.
        pub fn advanceTo(self: *Self, target_ns: u64) !bool {
            if (self.quit_requested) return true;
            if (target_ns < self.now_ns) return error.TimeCannotGoBackwards;
            self.now_ns = target_ns;
            return self.drain();
        }

        /// Processes queued and due work until the runtime becomes idle or
        /// quits.
        pub fn drain(self: *Self) !bool {
            if (self.quit_requested) return true;
            try self.boot();

            while (true) {
                switch (try self.step()) {
                    .idle => return false,
                    .progressed => continue,
                    .quit => return true,
                }
            }
        }

        /// Executes at most one logical step of work.
        pub fn step(self: *Self) !StepStatus {
            if (self.quit_requested) return .quit;
            try self.boot();

            if (self.pending.pop()) |msg| {
                return if (try self.processMessage(msg)) .quit else .progressed;
            }

            if (self.popDueMessage()) |msg| {
                return if (try self.processMessage(msg)) .quit else .progressed;
            }

            return .idle;
        }

        /// Renders the current frame into any writer without ANSI escapes.
        pub fn render(self: *Self, writer: anytype) !void {
            try self.ensureFrame();
            try writer.writeAll(self.frame_buffer.items);
        }

        /// Copies the current frame into a caller-owned buffer.
        pub fn snapshot(self: *Self, allocator: std.mem.Allocator) ![]u8 {
            try self.ensureFrame();
            return allocator.dupe(u8, self.frame_buffer.items);
        }

        /// Returns the cached frame bytes for inspection-heavy callers.
        pub fn frame(self: *Self) ![]const u8 {
            try self.ensureFrame();
            return self.frame_buffer.items;
        }

        /// Returns the semantic cursor from the current cached frame.
        pub fn cursor(self: *Self) !?ui.Cursor {
            try self.ensureFrame();
            return self.last_cursor;
        }

        /// Writes the authoritative structured tree snapshot for the current
        /// model state.
        pub fn writeTreeJson(self: *Self, writer: anytype) !void {
            try self.boot();
            try ui.renderModelJson(ModelType, self.allocator, &self.model, writer);
        }

        /// Rebuilds the cached frame only when the model marked itself dirty.
        fn ensureFrame(self: *Self) !void {
            if (!self.dirty) return;

            const rendered = try ui.renderModelSnapshot(ModelType, self.allocator, &self.model, &self.frame_buffer, .{
                .ansi = false,
            });
            self.last_cursor = rendered.cursor;
            self.dirty = false;
        }

        /// Routes one message through the model and applies any returned
        /// command.
        fn processMessage(self: *Self, msg: Msg) !bool {
            if (msg == .quit) {
                self.finish();
                return true;
            }

            const result: UpdateResult = try self.model.update(msg);
            if (result.command) |command| {
                try self.dispatchCommand(command);
            }
            if (result.redraw) {
                self.dirty = true;
            }
            if (result.quit) {
                self.finish();
            }
            return result.quit;
        }

        /// Handles emit and timer commands against local queues.
        fn dispatchCommand(self: *Self, maybe_command: ?Command) !void {
            const command = maybe_command orelse return;
            switch (command) {
                .none => {},
                .emit => |msg| try self.pending.push(self.allocator, msg),
                .tick => |tick| try self.scheduled.append(self.allocator, .{
                    .deadline_ns = self.now_ns + tick.delay_ns,
                    .msg = tick.message,
                }),
            }
        }

        /// Freezes the runtime after quit so later calls remain stable and
        /// queued work can no longer mutate the model.
        fn finish(self: *Self) void {
            self.quit_requested = true;
            self.pending.clearRetainingCapacity();
            self.scheduled.clearRetainingCapacity();
        }

        /// Returns the earliest timer whose deadline has passed.
        fn popDueMessage(self: *Self) ?Msg {
            var match_index: ?usize = null;
            var earliest_due: u64 = std.math.maxInt(u64);

            for (self.scheduled.items, 0..) |scheduled, index| {
                if (scheduled.deadline_ns > self.now_ns) continue;
                if (scheduled.deadline_ns <= earliest_due) {
                    earliest_due = scheduled.deadline_ns;
                    match_index = index;
                }
            }

            if (match_index) |index| {
                return self.scheduled.swapRemove(index).msg;
            }

            return null;
        }
    };
}

test "headless program advances timers deterministically" {
    const Msg = tea.Message(void);

    const Model = struct {
        ticks: usize = 0,

        pub fn init(self: *@This()) ?tea.Cmd(Msg) {
            _ = self;
            return tea.tickAfter(Msg, 10 * std.time.ns_per_ms, .{
                .timer = .{ .id = 1 },
            });
        }

        pub fn update(self: *@This(), msg: Msg) !tea.Update(Msg) {
            return switch (msg) {
                .timer => blk: {
                    self.ticks += 1;
                    break :blk tea.Update(Msg).quitNow();
                },
                else => tea.Update(Msg).noop(),
            };
        }

        pub fn view(self: *const @This(), writer: anytype) !void {
            try std.fmt.format(writer, "ticks={d}", .{self.ticks});
        }
    };

    var program = HeadlessProgram(Model, void).init(std.testing.allocator, .{});
    defer program.deinit();

    try std.testing.expect(!(try program.drain()));
    try std.testing.expectEqual(@as(usize, 0), program.model.ticks);
    try std.testing.expect(!(try program.advanceBy(9 * std.time.ns_per_ms)));
    try std.testing.expectEqual(@as(usize, 0), program.model.ticks);
    try std.testing.expect(try program.advanceBy(1 * std.time.ns_per_ms));
    try std.testing.expectEqual(@as(usize, 1), program.model.ticks);
}

test "headless runtime injects one initial resize before init output" {
    const Msg = tea.Message(void);

    const Model = struct {
        saw_resize: bool = false,
        events: usize = 0,

        pub fn init(self: *@This()) ?tea.Cmd(Msg) {
            self.events += 1;
            return tea.emit(Msg, .{ .user = {} });
        }

        pub fn update(self: *@This(), msg: Msg) !tea.Update(Msg) {
            switch (msg) {
                .resize => {
                    self.saw_resize = true;
                    self.events += 1;
                    return .{};
                },
                .user => {
                    self.events += 1;
                    return tea.Update(Msg).quitNow();
                },
                else => return tea.Update(Msg).noop(),
            }
        }

        pub fn compose(self: *const @This(), tree: *ui.Tree) !ui.NodeId {
            return tree.text(if (self.saw_resize) "resize-first" else "missing-resize");
        }
    };

    var program = HeadlessProgram(Model, void).init(std.testing.allocator, .{});
    defer program.deinit();

    try std.testing.expect(try program.drain());
    try std.testing.expect(program.model.saw_resize);
    try std.testing.expectEqual(@as(usize, 3), program.model.events);
    try std.testing.expectEqualStrings("resize-first", try program.frame());
}

test "headless runtime stays stable after quit" {
    const Msg = tea.Message(void);

    const Model = struct {
        updates: usize = 0,

        pub fn update(self: *@This(), msg: Msg) !tea.Update(Msg) {
            self.updates += 1;
            return switch (msg) {
                .quit => tea.Update(Msg).quitNow(),
                else => tea.Update(Msg).quitNow(),
            };
        }

        pub fn compose(self: *const @This(), tree: *ui.Tree) !ui.NodeId {
            return tree.text(try std.fmt.allocPrint(tree.allocator(), "updates={d}", .{self.updates}));
        }
    };

    var program = HeadlessProgram(Model, void).init(std.testing.allocator, .{});
    defer program.deinit();

    try std.testing.expect(try program.drain());
    try std.testing.expectEqualStrings("updates=1", try program.frame());
    try std.testing.expect(try program.drain());
    try std.testing.expectEqualStrings("updates=1", try program.frame());
    try std.testing.expectError(error.ProgramExited, program.send(.{ .user = {} }));

    const snapshot = try program.snapshot(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expectEqualStrings("updates=1", snapshot);
}
