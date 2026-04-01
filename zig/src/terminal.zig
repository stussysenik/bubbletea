const std = @import("std");

/// Viewport dimensions seen by the host.
pub const Size = struct {
    width: u16 = 80,
    height: u16 = 24,
};

/// Thin terminal wrapper for raw-mode setup, polling, and size queries.
pub const Terminal = struct {
    stdin: std.fs.File = std.fs.File.stdin(),
    stdout: std.fs.File = std.fs.File.stdout(),
    original_state: ?std.posix.termios = null,

    pub fn init() Terminal {
        return .{};
    }

    /// Switches stdin into a non-canonical mode that delivers keys immediately.
    pub fn enableRawMode(self: *Terminal) !void {
        if (!self.stdin.isTty()) return;

        var raw = try std.posix.tcgetattr(self.stdin.handle);
        self.original_state = raw;

        raw.iflag.BRKINT = false;
        raw.iflag.ICRNL = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;
        raw.iflag.IXON = false;
        raw.oflag.OPOST = false;
        raw.cflag.CSIZE = .CS8;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.IEXTEN = false;
        raw.lflag.ISIG = false;
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 1;

        try std.posix.tcsetattr(self.stdin.handle, .FLUSH, raw);
    }

    /// Restores the terminal when raw mode was previously enabled.
    pub fn restore(self: *Terminal) void {
        if (self.original_state) |state| {
            std.posix.tcsetattr(self.stdin.handle, .FLUSH, state) catch {};
            self.original_state = null;
        }
    }

    pub fn readInput(self: *const Terminal, buffer: []u8) !usize {
        return std.posix.read(self.stdin.handle, buffer);
    }

    /// Writes an OSC 52 clipboard update when stdout is a TTY.
    pub fn writeClipboard(self: *const Terminal, text: []const u8) !void {
        if (!self.stdout.isTty()) return;

        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(std.heap.page_allocator);

        try appendOsc52Clipboard(&buffer, std.heap.page_allocator, text);
        try self.stdout.writeAll(buffer.items);
    }

    /// Requests clipboard text from OSC 52 capable terminals.
    pub fn requestClipboard(self: *const Terminal) !void {
        if (!self.stdout.isTty()) return;

        var buffer: [9]u8 = undefined;
        const sequence = osc52ClipboardQuery(&buffer);
        try self.stdout.writeAll(sequence);
    }

    /// Blocks until input is available or the timeout expires.
    pub fn pollInput(self: *const Terminal, timeout_ms: i32) !bool {
        var pollfds = [_]std.posix.pollfd{.{
            .fd = self.stdin.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};

        return switch (try std.posix.poll(&pollfds, timeout_ms)) {
            0 => false,
            else => (pollfds[0].revents & std.posix.POLL.IN) != 0,
        };
    }

    /// Returns the terminal size, falling back to a sensible default for
    /// non-interactive hosts.
    pub fn size(self: *const Terminal) !Size {
        if (!self.stdout.isTty()) return .{};

        var winsize: std.posix.winsize = .{
            .row = 0,
            .col = 0,
            .xpixel = 0,
            .ypixel = 0,
        };

        const rc = std.posix.system.ioctl(
            self.stdout.handle,
            std.posix.T.IOCGWINSZ,
            @intFromPtr(&winsize),
        );

        return switch (std.posix.errno(rc)) {
            .SUCCESS => .{
                .width = if (winsize.col == 0) 80 else winsize.col,
                .height = if (winsize.row == 0) 24 else winsize.row,
            },
            .NOTTY => .{},
            else => error.GetWindowSizeFailed,
        };
    }
};

// Encodes one OSC 52 clipboard write sequence for terminals that support it.
fn appendOsc52Clipboard(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8) !void {
    try buffer.appendSlice(allocator, "\x1b]52;c;");
    const encoded_len = std.base64.standard.Encoder.calcSize(text.len);
    const encoded = try buffer.addManyAsSlice(allocator, encoded_len);
    _ = std.base64.standard.Encoder.encode(encoded, text);
    try buffer.append(allocator, 0x07);
}

// Produces an OSC 52 clipboard query using BEL termination.
fn osc52ClipboardQuery(buffer: *[9]u8) []const u8 {
    @memcpy(buffer, "\x1b]52;c;?\x07");
    return buffer;
}

test "osc52 clipboard sequence encodes utf8 text" {
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    try appendOsc52Clipboard(&buffer, std.testing.allocator, "zig tea");
    try std.testing.expectEqualStrings("\x1b]52;c;emlnIHRlYQ==\x07", buffer.items);
}

test "osc52 clipboard query is emitted with bel terminator" {
    var buffer: [9]u8 = undefined;
    try std.testing.expectEqualStrings("\x1b]52;c;?\x07", osc52ClipboardQuery(&buffer));
}
