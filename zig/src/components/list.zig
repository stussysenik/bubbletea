const std = @import("std");
const tea = @import("../tea.zig");
const ui = @import("../ui.zig");

pub const List = struct {
    items: []const []const u8,
    selected: usize = 0,

    pub fn init(items: []const []const u8) List {
        return .{
            .items = items,
        };
    }

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
            else => return false,
        }
    }

    pub fn selectedItem(self: *const List) ?[]const u8 {
        if (self.items.len == 0) return null;
        return self.items[self.selected];
    }

    pub fn view(self: *const List, writer: anytype) !void {
        for (self.items, 0..) |item, index| {
            const marker = if (index == self.selected) ">" else " ";
            try std.fmt.format(writer, "{s} {s}\n", .{ marker, item });
        }
    }

    pub fn compose(self: *const List, tree: *ui.Tree) !ui.NodeId {
        const rows = try tree.allocNodeIds(self.items.len);

        for (self.items, 0..) |item, index| {
            const marker = try tree.text(if (index == self.selected) "[x]" else "[ ]");
            const label = try tree.text(item);
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
