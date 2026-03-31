const std = @import("std");
const tea = @import("../tea.zig");
const ui = @import("../ui.zig");

/// Timer-driven spinner with no background threads or host-specific state.
pub const Spinner = struct {
    frames: []const []const u8 = &default_frames,
    frame_index: usize = 0,
    timer_id: u64,
    interval_ns: u64 = 90 * std.time.ns_per_ms,

    const default_frames = [_][]const u8{
        "-",
        "\\",
        "|",
        "/",
    };

    /// Binds the spinner to a timer identifier inside the program runtime.
    pub fn init(timer_id: u64) Spinner {
        return .{ .timer_id = timer_id };
    }

    /// Returns the next timer command needed to advance the spinner.
    pub fn tick(self: *const Spinner, comptime Msg: type) tea.Cmd(Msg) {
        return tea.tickAfter(Msg, self.interval_ns, .{
            .timer = .{
                .id = self.timer_id,
            },
        });
    }

    /// Consumes matching timer messages and schedules the next frame.
    pub fn update(self: *Spinner, comptime Msg: type, msg: Msg) ?tea.Cmd(Msg) {
        switch (msg) {
            .timer => |timer| {
                if (timer.id != self.timer_id) return null;
                self.frame_index = (self.frame_index + 1) % self.frames.len;
                return self.tick(Msg);
            },
            else => return null,
        }
    }

    /// Returns the frame currently selected by the timer loop.
    pub fn frame(self: *const Spinner) []const u8 {
        return self.frames[self.frame_index];
    }

    /// Exposes the current frame to the UI tree.
    pub fn compose(self: *const Spinner, tree: *ui.Tree) !ui.NodeId {
        return tree.text(self.frame());
    }
};

test "spinner advances when its timer fires" {
    const Msg = tea.Message(void);
    var spinner = Spinner.init(42);

    const first = spinner.frame();
    const cmd = spinner.update(Msg, .{
        .timer = .{
            .id = 42,
        },
    });

    try std.testing.expect(cmd != null);
    try std.testing.expect(!std.mem.eql(u8, first, spinner.frame()));
}
