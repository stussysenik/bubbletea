const std = @import("std");

/// Runtime knobs for the terminal renderer.
pub const Options = struct {
    alt_screen: bool = true,
    hide_cursor: bool = true,
    ansi_enabled: bool = true,
};

/// Minimal line-diff renderer that only rewrites rows whose text changed.
pub const Renderer = struct {
    allocator: std.mem.Allocator,
    stdout: std.fs.File,
    previous_frame: std.ArrayList(u8) = .empty,
    started: bool = false,
    options: Options,

    pub fn init(allocator: std.mem.Allocator, stdout: std.fs.File, options: Options) Renderer {
        return .{
            .allocator = allocator,
            .stdout = stdout,
            .options = options,
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.previous_frame.deinit(self.allocator);
    }

    /// Enables terminal modes needed for full-screen rendering.
    pub fn start(self: *Renderer) !void {
        if (self.started or !self.options.ansi_enabled) {
            self.started = true;
            return;
        }

        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(self.allocator);

        if (self.options.alt_screen) {
            try buffer.appendSlice(self.allocator, "\x1b[?1049h");
        }
        if (self.options.hide_cursor) {
            try buffer.appendSlice(self.allocator, "\x1b[?25l");
        }
        try buffer.appendSlice(self.allocator, "\x1b[2J\x1b[H");

        try self.stdout.writeAll(buffer.items);
        self.started = true;
    }

    /// Restores cursor visibility and screen state when the program exits.
    pub fn stop(self: *Renderer) !void {
        if (!self.started or !self.options.ansi_enabled) {
            self.started = false;
            return;
        }

        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(self.allocator);

        try buffer.appendSlice(self.allocator, "\x1b[0m");
        if (self.options.hide_cursor) {
            try buffer.appendSlice(self.allocator, "\x1b[?25h");
        }
        if (self.options.alt_screen) {
            try buffer.appendSlice(self.allocator, "\x1b[?1049l");
        } else {
            try buffer.append(self.allocator, '\n');
        }

        try self.stdout.writeAll(buffer.items);
        self.started = false;
    }

    /// Writes either the whole frame or a row-level diff depending on host
    /// capabilities.
    pub fn render(self: *Renderer, frame: []const u8) !void {
        if (std.mem.eql(u8, self.previous_frame.items, frame)) return;

        if (!self.options.ansi_enabled) {
            // Headless and piped output stay plain so tests and non-TTY hosts
            // can snapshot the frame directly.
            try self.stdout.writeAll(frame);
            self.previous_frame.clearRetainingCapacity();
            try self.previous_frame.appendSlice(self.allocator, frame);
            return;
        }

        // ANSI rendering rewrites only rows whose contents changed between
        // frames.
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(self.allocator);

        const writer = output.writer(self.allocator);
        var previous_lines = std.mem.splitScalar(u8, self.previous_frame.items, '\n');
        var next_lines = std.mem.splitScalar(u8, frame, '\n');
        var row: usize = 1;

        while (true) {
            const previous = previous_lines.next();
            const next = next_lines.next();

            if (previous == null and next == null) break;

            if (previous != null and next != null and std.mem.eql(u8, previous.?, next.?)) {
                row += 1;
                continue;
            }

            try std.fmt.format(writer, "\x1b[{d};1H\x1b[2K", .{row});
            if (next) |line| {
                try writer.writeAll(line);
            }

            row += 1;
        }

        try self.stdout.writeAll(output.items);
        self.previous_frame.clearRetainingCapacity();
        try self.previous_frame.appendSlice(self.allocator, frame);
    }
};
