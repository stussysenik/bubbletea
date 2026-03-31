const std = @import("std");
const ui = @import("../ui.zig");

pub const ProgressBar = struct {
    current: usize,
    total: usize,
    width: usize = 24,
    tone: ui.Tone = .accent,

    pub fn compose(self: *const ProgressBar, tree: *ui.Tree) !ui.NodeId {
        const safe_total = @max(self.total, 1);
        const clamped_current = @min(self.current, safe_total);
        const filled = (self.width * clamped_current) / safe_total;
        const empty = self.width - filled;
        const percent = (100 * clamped_current) / safe_total;

        const filled_text = try repeated(tree.allocator(), '#', filled);
        const empty_text = try repeated(tree.allocator(), '-', empty);
        const label = try std.fmt.allocPrint(tree.allocator(), "{d}%", .{percent});

        return tree.row(
            &.{
                try tree.text("["),
                try tree.textStyled(filled_text, .{ .tone = self.tone }),
                try tree.textStyled(empty_text, .{ .tone = .muted }),
                try tree.text("]"),
                try tree.textStyled(label, .{ .tone = .muted }),
            },
            .{ .gap = 1 },
        );
    }
};

fn repeated(allocator: std.mem.Allocator, value: u8, count: usize) ![]u8 {
    const buffer = try allocator.alloc(u8, count);
    @memset(buffer, value);
    return buffer;
}
