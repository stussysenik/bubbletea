const std = @import("std");
const tea = @import("../tea.zig");
const ui = @import("../ui.zig");

/// Single-selection list with keyboard navigation and a tree renderer.
pub const List = struct {
    items: []const []const u8,
    selected: usize = 0,
    empty_label: []const u8 = "(no results)",

    /// Creates a list over a caller-owned item slice.
    pub fn init(items: []const []const u8) List {
        return .{
            .items = items,
        };
    }

    /// Swaps the backing slice and clamps the selection to the new bounds.
    pub fn setItems(self: *List, items: []const []const u8) void {
        self.items = items;
        if (self.items.len == 0) {
            self.selected = 0;
            return;
        }
        if (self.selected >= self.items.len) {
            self.selected = self.items.len - 1;
        }
    }

    /// Applies navigation keys and reports whether the selection changed.
    pub fn update(self: *List, key: tea.Key) bool {
        if (self.items.len == 0) return false;

        switch (key) {
            .up => {
                if (self.selected == 0) return false;
                self.selected -= 1;
                return true;
            },
            .down => {
                if (self.selected + 1 >= self.items.len) return false;
                self.selected += 1;
                return true;
            },
            .home => {
                if (self.selected == 0) return false;
                self.selected = 0;
                return true;
            },
            .end => {
                const last_index = self.items.len - 1;
                if (self.selected == last_index) return false;
                self.selected = last_index;
                return true;
            },
            else => return false,
        }
    }

    /// Returns the currently selected item when the list is non-empty.
    pub fn selectedItem(self: *const List) ?[]const u8 {
        if (self.items.len == 0) return null;
        return self.items[self.selected];
    }

    /// Plain text rendering used by tests and non-tree hosts.
    pub fn view(self: *const List, writer: anytype) !void {
        if (self.items.len == 0) {
            try std.fmt.format(writer, "  {s}\n", .{self.empty_label});
            return;
        }

        for (self.items, 0..) |item, index| {
            const marker = if (index == self.selected) ">" else " ";
            try std.fmt.format(writer, "{s} {s}\n", .{ marker, item });
        }
    }

    /// Composes the list as styled rows inside the shared view tree.
    pub fn compose(self: *const List, tree: *ui.Tree) !ui.NodeId {
        if (self.items.len == 0) {
            return tree.textStyled(self.empty_label, .{ .tone = .muted });
        }

        const rows = try tree.allocNodeIds(self.items.len);

        for (self.items, 0..) |item, index| {
            const marker = try tree.textStyled(
                if (index == self.selected) "[x]" else "[ ]",
                .{ .tone = if (index == self.selected) .accent else .muted },
            );
            const label = if (index == self.selected)
                try tree.textStyled(item, .{ .tone = .success })
            else
                try tree.text(item);
            rows[index] = try tree.row(&.{ marker, label }, .{ .gap = 1 });
        }

        return tree.column(rows, .{ .gap = 0 });
    }
};

test "list navigation stays in bounds" {
    const items = [_][]const u8{ "one", "two", "three" };
    var list = List.init(&items);

    try std.testing.expect(list.update(.down));
    try std.testing.expectEqual(@as(usize, 1), list.selected);
    try std.testing.expect(list.update(.down));
    try std.testing.expectEqual(@as(usize, 2), list.selected);
    try std.testing.expect(!list.update(.down));
    try std.testing.expect(list.update(.up));
    try std.testing.expectEqual(@as(usize, 1), list.selected);
}
