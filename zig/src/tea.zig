const std = @import("std");
const input = @import("input.zig");
const ui = @import("ui.zig");
const renderer_mod = @import("renderer.zig");
const terminal_mod = @import("terminal.zig");

/// Input key type re-exported from the decoder layer.
pub const Key = input.Key;
/// Keyboard modifier flags carried by richer key protocols.
pub const KeyModifiers = input.KeyModifiers;
/// Optional press/repeat/release metadata for decoded keys.
pub const KeyEventKind = input.KeyEventKind;
/// Higher-level decoded terminal event.
pub const InputEvent = input.Event;
/// Normalized mouse action metadata.
pub const MouseAction = input.MouseAction;
/// Normalized mouse button metadata.
pub const MouseButton = input.MouseButton;
/// Modifier flags attached to mouse events.
pub const MouseModifiers = input.MouseModifiers;
/// Pointer event as reported by the terminal host.
pub const MouseEvent = input.MouseEvent;
/// Terminal viewport size.
pub const Size = terminal_mod.Size;
/// Terminal renderer implementation.
pub const Renderer = renderer_mod.Renderer;
/// Terminal host abstraction.
pub const Terminal = terminal_mod.Terminal;
/// Terminal mouse tracking mode.
pub const MouseMode = renderer_mod.MouseMode;

/// Timer identity passed back to models when delayed commands fire.
pub const TimerMsg = struct {
    id: u64,
};

/// Standard runtime message envelope used by the interactive host.
pub fn Message(comptime UserMsg: type) type {
    return union(enum) {
        none,
        quit,
        key: Key,
        paste: []const u8,
        focus_gained,
        focus_lost,
        mouse: MouseEvent,
        resize: Size,
        timer: TimerMsg,
        user: UserMsg,
    };
}

/// Command envelope that lets models emit messages or schedule timers.
pub fn Cmd(comptime Msg: type) type {
    return union(enum) {
        none,
        emit: Msg,
        tick: struct {
            delay_ns: u64,
            message: Msg,
        },
    };
}

/// Result returned from `update`, including redraw and quit semantics.
pub fn Update(comptime Msg: type) type {
    return struct {
        command: ?Cmd(Msg) = null,
        redraw: bool = true,
        quit: bool = false,

        /// Leaves the model untouched and skips rendering work.
        pub fn noop() @This() {
            return .{ .redraw = false };
        }

        /// Requests an additional command after the update completes.
        pub fn withCommand(command: Cmd(Msg)) @This() {
            return .{ .command = command };
        }

        /// Exits the runtime after the current update cycle.
        pub fn quitNow() @This() {
            return .{ .quit = true };
        }
    };
}

/// Convenience wrapper for pushing a message back into the runtime.
pub fn emit(comptime Msg: type, message: Msg) Cmd(Msg) {
    return .{ .emit = message };
}

/// Convenience wrapper for scheduling a delayed message on the timer queue.
pub fn tickAfter(comptime Msg: type, delay_ns: u64, message: Msg) Cmd(Msg) {
    return .{
        .tick = .{
            .delay_ns = delay_ns,
            .message = message,
        },
    };
}

// Compact queue used for both pending messages and deterministic scheduling.
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

/// Interactive terminal program that drives a model with decoded input,
/// timers, resize events, and incremental rendering.
pub fn Program(comptime ModelType: type, comptime UserMsg: type) type {
    comptime {
        if (!@hasDecl(ModelType, "update")) {
            @compileError("ModelType must declare update(self: *ModelType, msg: Msg) !tea.Update(Msg)");
        }
        if (!@hasDecl(ModelType, "view") and !@hasDecl(ModelType, "compose")) {
            @compileError("ModelType must declare either view(self: *const ModelType, writer: anytype) !void or compose(self: *const ModelType, tree: *ui.Tree) !ui.NodeId");
        }
    }

    const Msg = Message(UserMsg);
    const Command = Cmd(Msg);
    const UpdateResult = Update(Msg);

    const ScheduledMessage = struct {
        deadline_ns: u64,
        msg: Msg,
    };

    return struct {
        allocator: std.mem.Allocator,
        model: ModelType,
        terminal: Terminal = Terminal.init(),
        renderer: Renderer,
        input_decoder: input.Decoder,
        pending: Queue(Msg) = .{},
        scheduled: std.ArrayList(ScheduledMessage) = .empty,
        frame_buffer: std.ArrayList(u8) = .empty,
        last_size: Size = .{},
        dirty: bool = true,
        options: Options,

        const Self = @This();

        pub const Options = struct {
            alt_screen: bool = true,
            use_raw_mode: bool = true,
            poll_interval_ms: i32 = 16,
            kitty_keyboard: bool = true,
            bracketed_paste: bool = true,
            focus_reporting: bool = true,
            mouse_mode: MouseMode = .none,
        };

        /// Creates a terminal program around the provided model instance.
        pub fn init(allocator: std.mem.Allocator, model: ModelType, options: Options) Self {
            const terminal = Terminal.init();
            return .{
                .allocator = allocator,
                .model = model,
                .terminal = terminal,
                .renderer = Renderer.init(allocator, terminal.stdout, .{
                    .alt_screen = options.alt_screen,
                    .hide_cursor = true,
                    .ansi_enabled = terminal.stdout.isTty(),
                    .kitty_keyboard = options.kitty_keyboard,
                    .bracketed_paste = options.bracketed_paste,
                    .focus_reporting = options.focus_reporting,
                    .mouse_mode = options.mouse_mode,
                }),
                .input_decoder = input.Decoder.init(allocator),
                .options = options,
            };
        }

        /// Releases queues, renderer state, and buffered frames.
        pub fn deinit(self: *Self) void {
            self.pending.deinit(self.allocator);
            self.scheduled.deinit(self.allocator);
            self.frame_buffer.deinit(self.allocator);
            self.input_decoder.deinit();
            self.renderer.deinit();
        }

        /// Queues a message to be processed on the next event loop turn.
        pub fn send(self: *Self, msg: Msg) !void {
            try self.pending.push(self.allocator, msg);
        }

        /// Boots the terminal host, injects the first resize, runs `init`
        /// exactly once, renders the first frame, and stays in the event loop
        /// until the model requests quit. Once quit is requested, the host
        /// tears down terminal state and returns the final model unchanged.
        pub fn run(self: *Self) !ModelType {
            if (self.options.use_raw_mode) {
                try self.terminal.enableRawMode();
            }
            defer self.terminal.restore();

            try self.renderer.start();
            defer self.renderer.stop() catch {};

            self.last_size = try self.terminal.size();
            try self.send(.{ .resize = self.last_size });

            if (@hasDecl(ModelType, "init")) {
                try self.dispatchCommand(self.model.init());
            }

            try self.render();

            while (true) {
                if (try self.nextMessage()) |msg| {
                    if (try self.processMessage(msg)) break;
                    if (self.dirty) {
                        try self.render();
                    }
                }
            }

            return self.model;
        }

        /// Routes one message through the model update function.
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

        /// Renders the current model snapshot through either `compose` or
        /// `view`, then hands the frame to the terminal renderer.
        fn render(self: *Self) !void {
            const snapshot = try ui.renderModelSnapshot(ModelType, self.allocator, &self.model, &self.frame_buffer, .{
                .ansi = self.renderer.options.ansi_enabled,
            });
            try self.renderer.renderFrame(.{
                .bytes = snapshot.frame,
                .cursor = snapshot.cursor,
            });
            self.dirty = false;
        }

        /// Pulls the next available message from pending work, decoded input,
        /// timers, or resize polling.
        fn nextMessage(self: *Self) !?Msg {
            if (self.pending.pop()) |msg| {
                return msg;
            }

            // Decoder state is drained before more syscalls so one read can
            // yield multiple logical input events.
            if (self.input_decoder.nextEvent()) |event| {
                return self.messageFromInputEvent(event);
            }

            const now = nowNs();
            if (self.popDueMessage(now)) |msg| {
                return msg;
            }

            const timeout_ms = self.nextPollTimeout(now);
            if (try self.terminal.pollInput(timeout_ms)) {
                var buffer: [32]u8 = undefined;
                const read_len = try self.terminal.readInput(&buffer);
                if (read_len > 0) {
                    try self.input_decoder.feed(buffer[0..read_len]);
                    if (self.input_decoder.nextEvent()) |event| {
                        return self.messageFromInputEvent(event);
                    }
                }
            }

            const size = try self.terminal.size();
            if (size.width != self.last_size.width or size.height != self.last_size.height) {
                self.last_size = size;
                return .{ .resize = size };
            }

            if (self.pending.pop()) |msg| {
                return msg;
            }

            // If polling timed out with a partial escape sequence buffered,
            // treat it as a standalone key rather than waiting forever.
            if (self.input_decoder.flushEvent()) |event| {
                return self.messageFromInputEvent(event);
            }

            return null;
        }

        /// Executes commands synchronously against the local queues.
        fn dispatchCommand(self: *Self, maybe_command: ?Command) !void {
            const command = maybe_command orelse return;
            switch (command) {
                .none => {},
                .emit => |msg| try self.pending.push(self.allocator, msg),
                .tick => |tick| try self.scheduled.append(self.allocator, .{
                    .deadline_ns = nowNs() + tick.delay_ns,
                    .msg = tick.message,
                }),
            }
        }

        /// Converts a normalized decoder event into the runtime message union.
        fn messageFromInputEvent(self: *Self, event: input.Event) Msg {
            _ = self;
            return switch (event) {
                .key => |key| .{ .key = key },
                .paste => |text| .{ .paste = text },
                .focus_gained => .focus_gained,
                .focus_lost => .focus_lost,
                .mouse => |mouse| .{ .mouse = mouse },
            };
        }

        /// Removes the earliest scheduled message whose deadline has passed.
        fn popDueMessage(self: *Self, now: u64) ?Msg {
            var match_index: ?usize = null;
            var earliest_due: u64 = std.math.maxInt(u64);

            for (self.scheduled.items, 0..) |scheduled, index| {
                if (scheduled.deadline_ns > now) continue;
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

        /// Polls the terminal no longer than necessary when timers are queued.
        fn nextPollTimeout(self: *Self, now: u64) i32 {
            var timeout_ms = self.options.poll_interval_ms;

            for (self.scheduled.items) |scheduled| {
                if (scheduled.deadline_ns <= now) return 0;

                const remaining_ns = scheduled.deadline_ns - now;
                const rounded_ms = (remaining_ns + std.time.ns_per_ms - 1) / std.time.ns_per_ms;
                const clamped_ms = @min(rounded_ms, @as(u64, @intCast(std.math.maxInt(i32))));
                timeout_ms = @min(timeout_ms, @as(i32, @intCast(clamped_ms)));
            }

            return timeout_ms;
        }
    };
}

// Centralized timestamp helper keeps host logic testable.
fn nowNs() u64 {
    return @intCast(std.time.nanoTimestamp());
}

test "queue compacts after pops" {
    var queue: Queue(u8) = .{};
    defer queue.deinit(std.testing.allocator);

    try queue.push(std.testing.allocator, 1);
    try queue.push(std.testing.allocator, 2);
    try queue.push(std.testing.allocator, 3);

    try std.testing.expectEqual(@as(?u8, 1), queue.pop());
    try std.testing.expectEqual(@as(?u8, 2), queue.pop());
    try std.testing.expectEqual(@as(?u8, 3), queue.pop());
    try std.testing.expectEqual(@as(?u8, null), queue.pop());
}
