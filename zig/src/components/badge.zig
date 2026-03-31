const ui = @import("../ui.zig");

pub const Badge = struct {
    label: []const u8,
    tone: ui.Tone = .accent,

    pub fn init(label: []const u8, tone: ui.Tone) Badge {
        return .{
            .label = label,
            .tone = tone,
        };
    }

    pub fn compose(self: *const Badge, tree: *ui.Tree) !ui.NodeId {
        return tree.box(
            try tree.textStyled(self.label, .{ .tone = self.tone }),
            .{
                .padding = ui.Insets.symmetric(0, 1),
                .tone = self.tone,
            },
        );
    }
};
