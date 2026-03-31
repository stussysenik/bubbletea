const std = @import("std");

pub const Size = struct {
    width: u16 = 80,
    height: u16 = 24,
};

pub const Terminal = struct {
    stdin: std.fs.File = std.fs.File.stdin(),
    stdout: std.fs.File = std.fs.File.stdout(),
    original_state: ?std.posix.termios = null,

    pub fn init() Terminal {
        return .{};
    }

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

    pub fn restore(self: *Terminal) void {
        if (self.original_state) |state| {
            std.posix.tcsetattr(self.stdin.handle, .FLUSH, state) catch {};
            self.original_state = null;
        }
    }

    pub fn readInput(self: *const Terminal, buffer: []u8) !usize {
        return std.posix.read(self.stdin.handle, buffer);
    }

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
