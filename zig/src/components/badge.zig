const ui = @import("../ui.zig");

/// Small boxed label used to surface app or host capabilities.
pub const Badge = struct {
    label: []const u8,
    tone: ui.Tone = .accent,

    /// Creates a badge with a fixed label and visual tone.
    pub fn init(label: []const u8, tone: ui.Tone) Badge {
        return .{
            .label = label,
            .tone = tone,
        };
    }

    /// Renders the badge as a boxed text node inside the shared view tree.
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
