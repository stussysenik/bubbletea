const std = @import("std");
const tea = @import("tea.zig");
const ui = @import("ui.zig");

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
        now_ns: u64 = 0,

        const Self = @This();
        pub const StepStatus = Step;

        pub fn init(allocator: std.mem.Allocator, model: ModelType) Self {
            return .{
                .allocator = allocator,
                .model = model,
            };
        }

        pub fn deinit(self: *Self) void {
            self.pending.deinit(self.allocator);
            self.scheduled.deinit(self.allocator);
            self.frame_buffer.deinit(self.allocator);
        }

        pub fn boot(self: *Self) !void {
            if (self.initialized) return;
            self.initialized = true;

            if (@hasDecl(ModelType, "init")) {
                try self.dispatchCommand(self.model.init());
            }
        }

        pub fn send(self: *Self, msg: Msg) !void {
            try self.pending.push(self.allocator, msg);
        }

        pub fn advanceBy(self: *Self, delta_ns: u64) !bool {
            self.now_ns += delta_ns;
            return self.drain();
        }

        pub fn advanceTo(self: *Self, target_ns: u64) !bool {
            if (target_ns < self.now_ns) return error.TimeCannotGoBackwards;
            self.now_ns = target_ns;
            return self.drain();
        }

        pub fn drain(self: *Self) !bool {
            try self.boot();

            while (true) {
                switch (try self.step()) {
                    .idle => return false,
                    .progressed => continue,
                    .quit => return true,
                }
            }
        }

        pub fn step(self: *Self) !StepStatus {
            try self.boot();

            if (self.pending.pop()) |msg| {
                return if (try self.processMessage(msg)) .quit else .progressed;
            }

            if (self.popDueMessage()) |msg| {
                return if (try self.processMessage(msg)) .quit else .progressed;
            }

            return .idle;
        }

        pub fn render(self: *Self, writer: anytype) !void {
            try self.ensureFrame();
            try writer.writeAll(self.frame_buffer.items);
        }

        pub fn snapshot(self: *Self, allocator: std.mem.Allocator) ![]u8 {
            try self.ensureFrame();
            return allocator.dupe(u8, self.frame_buffer.items);
        }

        pub fn frame(self: *Self) ![]const u8 {
            try self.ensureFrame();
            return self.frame_buffer.items;
        }

        fn ensureFrame(self: *Self) !void {
            if (!self.dirty) return;

            try ui.renderModel(ModelType, self.allocator, &self.model, &self.frame_buffer, .{
                .ansi = false,
            });
            self.dirty = false;
        }

        fn processMessage(self: *Self, msg: Msg) !bool {
            if (msg == .quit) {
                return true;
            }

            const result: UpdateResult = try self.model.update(msg);
            if (result.command) |command| {
                try self.dispatchCommand(command);
            }
            if (result.redraw) {
                self.dirty = true;
            }
            return result.quit;
        }

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
