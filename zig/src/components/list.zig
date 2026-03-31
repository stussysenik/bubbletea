const std = @import("std");
const tea = @import("../tea.zig");
const ui = @import("../ui.zig");

/// Single-selection list with keyboard navigation and a tree renderer.
pub const List = struct {
    items: []const []const u8,
    selected: usize = 0,
    empty_label: []const u8 = "(no results)",

    /// Optional composition-time metadata for browser-targetable list rows.
    pub const ComposeOptions = struct {
        action_kind: ?[]const u8 = null,
    };

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

        if (key.isCode(.up)) {
            if (self.selected == 0) return false;
            self.selected -= 1;
            return true;
        }
        if (key.isCode(.down)) {
            if (self.selected + 1 >= self.items.len) return false;
            self.selected += 1;
            return true;
        }
        if (key.isCode(.home)) {
            if (self.selected == 0) return false;
            self.selected = 0;
            return true;
        }
        if (key.isCode(.end)) {
            const last_index = self.items.len - 1;
            if (self.selected == last_index) return false;
            self.selected = last_index;
            return true;
        }
        return false;
    }

    /// Applies wheel events without requiring the caller to map them to keys.
    pub fn updateMouse(self: *List, mouse: tea.MouseEvent) bool {
        if (mouse.action != .scroll) return false;

        return switch (mouse.button) {
            .wheel_up => self.update(tea.Key.up),
            .wheel_down => self.update(tea.Key.down),
            else => false,
        };
    }

    /// Returns the currently selected item when the list is non-empty.
    pub fn selectedItem(self: *const List) ?[]const u8 {
        if (self.items.len == 0) return null;
        return self.items[self.selected];
    }

    /// Selects an explicit row index when it exists.
    pub fn setSelected(self: *List, index: usize) bool {
        if (index >= self.items.len) return false;
        self.selected = index;
        return true;
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
        return self.composeWithOptions(tree, .{});
    }

    /// Composes the list and optionally tags each row with browser action
    /// metadata.
    pub fn composeWithOptions(self: *const List, tree: *ui.Tree, options: ComposeOptions) !ui.NodeId {
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
            const row = try tree.row(&.{ marker, label }, .{ .gap = 1 });
            rows[index] = if (options.action_kind) |action_kind|
                try tree.box(row, .{
                    .action = .{
                        .kind = action_kind,
                        .value = index,
                    },
                    .border = .none,
                })
            else
                row;
        }

        return tree.column(rows, .{ .gap = 0 });
    }
};

test "list navigation stays in bounds" {
    const items = [_][]const u8{ "one", "two", "three" };
    var list = List.init(&items);

    try std.testing.expect(list.update(tea.Key.down));
    try std.testing.expectEqual(@as(usize, 1), list.selected);
    try std.testing.expect(list.update(tea.Key.down));
    try std.testing.expectEqual(@as(usize, 2), list.selected);
    try std.testing.expect(!list.update(tea.Key.down));
    try std.testing.expect(list.update(tea.Key.up));
    try std.testing.expectEqual(@as(usize, 1), list.selected);
}

test "list reacts to mouse wheel navigation" {
    const items = [_][]const u8{ "one", "two", "three" };
    var list = List.init(&items);

    try std.testing.expect(list.updateMouse(.{
        .x = 0,
        .y = 0,
        .button = .wheel_down,
        .action = .scroll,
    }));
    try std.testing.expectEqual(@as(usize, 1), list.selected);
    try std.testing.expect(list.updateMouse(.{
        .x = 0,
        .y = 0,
        .button = .wheel_up,
        .action = .scroll,
    }));
    try std.testing.expectEqual(@as(usize, 0), list.selected);
}

test "list can compose browser action metadata" {
    const items = [_][]const u8{ "one", "two" };
    const list = List.init(&items);

    var tree = ui.Tree.init(std.testing.allocator);
    defer tree.deinit();

    const root = try list.composeWithOptions(&tree, .{ .action_kind = "list_item" });
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    try tree.writeJson(buffer.writer(std.testing.allocator), root);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"action\":{\"kind\":\"list_item\",\"value\":0}") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"action\":{\"kind\":\"list_item\",\"value\":1}") != null);
}
