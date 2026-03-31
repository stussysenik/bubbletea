const std = @import("std");
const ui = @import("../ui.zig");

/// Read-only key/value inspector for summaries, previews, and detail panes.
pub const Inspector = struct {
    entries: []const Entry,
    empty_label: []const u8 = "(no fields)",
    label_tone: ui.Tone = .muted,
    gap: usize = 0,

    /// One labeled value row inside the inspector.
    pub const Entry = struct {
        label: []const u8,
        value: []const u8,
        tone: ui.Tone = .normal,
    };

    /// Plain text fallback used by headless tests and simple hosts.
    pub fn view(self: *const Inspector, writer: anytype) !void {
        if (self.entries.len == 0) {
            try writer.writeAll(self.empty_label);
            return;
        }

        for (self.entries, 0..) |entry, index| {
            try std.fmt.format(writer, "{s}: {s}", .{ entry.label, entry.value });
            if (index + 1 < self.entries.len) {
                try writer.writeByte('\n');
            }
        }
    }

    /// Composes labeled rows into the shared view tree.
    pub fn compose(self: *const Inspector, tree: *ui.Tree) !ui.NodeId {
        if (self.entries.len == 0) {
            return tree.textStyled(self.empty_label, .{ .tone = .muted });
        }

        const rows = try tree.allocNodeIds(self.entries.len);
        for (self.entries, 0..) |entry, index| {
            // Labels stay visually secondary so values carry the semantic tone.
            const label = try tree.textStyled(
                try std.fmt.allocPrint(tree.allocator(), "{s}:", .{entry.label}),
                .{ .tone = self.label_tone },
            );
            const value = if (entry.value.len == 0)
                try tree.textStyled("(empty)", .{ .tone = .muted })
            else
                try tree.textStyled(entry.value, .{ .tone = entry.tone });
            rows[index] = try tree.row(&.{ label, value }, .{ .gap = 1 });
        }

        return tree.column(rows, .{ .gap = self.gap });
    }
};

test "inspector renders labeled entries" {
    const entries = [_]Inspector.Entry{
        .{ .label = "name", .value = "bubbletea-zig", .tone = .accent },
        .{ .label = "target", .value = "cli + wasm", .tone = .warning },
    };

    var tree = ui.Tree.init(std.testing.allocator);
    defer tree.deinit();

    const inspector = Inspector{ .entries = &entries };
    const root = try inspector.compose(&tree);
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    try tree.render(buffer.writer(std.testing.allocator), root, .{ .ansi = false });
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "name:") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "bubbletea-zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "target:") != null);
}

test "inspector falls back when empty" {
    var tree = ui.Tree.init(std.testing.allocator);
    defer tree.deinit();

    const inspector = Inspector{ .entries = &.{} };
    const root = try inspector.compose(&tree);
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    try tree.render(buffer.writer(std.testing.allocator), root, .{ .ansi = false });
    try std.testing.expectEqualStrings("(no fields)", buffer.items);
}
