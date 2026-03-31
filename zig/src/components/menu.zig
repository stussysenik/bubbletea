const std = @import("std");
const tea = @import("../tea.zig");
const ui = @import("../ui.zig");

/// Simple action menu with one active item and optional descriptive text.
pub const Menu = struct {
    items: []const Item,
    selected: usize = 0,
    active: bool = true,
    empty_label: []const u8 = "(no menu items)",

    /// One menu row plus its optional detail copy.
    pub const Item = struct {
        label: []const u8,
        detail: []const u8 = "",
        tone: ui.Tone = .accent,
    };

    /// Creates a menu over a caller-owned item slice.
    pub fn init(items: []const Item) Menu {
        return .{ .items = items };
    }

    /// Toggles whether the menu should render its active selection strongly.
    pub fn setActive(self: *Menu, active: bool) void {
        self.active = active;
    }

    /// Returns the selected item when one exists.
    pub fn selectedItem(self: *const Menu) ?Item {
        if (self.items.len == 0) return null;
        return self.items[self.selected];
    }

    /// Applies standard menu navigation keys.
    pub fn update(self: *Menu, key: tea.Key) bool {
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

    /// Applies wheel input without forcing callers to translate it.
    pub fn updateMouse(self: *Menu, mouse: tea.MouseEvent) bool {
        if (mouse.action != .scroll) return false;

        return switch (mouse.button) {
            .wheel_up => self.update(.up),
            .wheel_down => self.update(.down),
            else => false,
        };
    }

    /// Reports whether a key should activate the selected menu item.
    pub fn shouldActivate(self: *const Menu, key: tea.Key) bool {
        _ = self;
        return switch (key) {
            .enter => true,
            .character => |value| value == ' ',
            else => false,
        };
    }

    /// Plain text fallback for simple hosts and tests.
    pub fn view(self: *const Menu, writer: anytype) !void {
        if (self.items.len == 0) {
            try writer.writeAll(self.empty_label);
            return;
        }

        for (self.items, 0..) |item, index| {
            const marker = if (index == self.selected and self.active) ">" else " ";
            try std.fmt.format(writer, "{s} {s}", .{ marker, item.label });
            if (item.detail.len != 0) {
                try std.fmt.format(writer, " - {s}", .{item.detail});
            }
            if (index + 1 < self.items.len) {
                try writer.writeByte('\n');
            }
        }
    }

    /// Composes the menu as stacked labels with secondary detail text.
    pub fn compose(self: *const Menu, tree: *ui.Tree) !ui.NodeId {
        if (self.items.len == 0) {
            return tree.textStyled(self.empty_label, .{ .tone = .muted });
        }

        const rows = try tree.allocNodeIds(self.items.len);
        for (self.items, 0..) |item, index| {
            const selected = index == self.selected;
            const marker = try tree.textStyled(
                if (selected and self.active) ">" else if (selected) "*" else " ",
                .{ .tone = if (selected) item.tone else .muted },
            );
            const label = try tree.textStyled(
                item.label,
                .{ .tone = if (selected and self.active) item.tone else .normal },
            );

            if (item.detail.len == 0) {
                rows[index] = try tree.row(&.{ marker, label }, .{ .gap = 1 });
                continue;
            }

            const detail = try tree.textStyled(
                item.detail,
                .{ .tone = if (selected) .muted else .muted },
            );
            rows[index] = try tree.column(
                &.{
                    try tree.row(&.{ marker, label }, .{ .gap = 1 }),
                    try tree.row(&.{ try tree.text(" "), detail }, .{ .gap = 1 }),
                },
                .{ .gap = 0 },
            );
        }

        return tree.column(rows, .{ .gap = 1 });
    }
};

test "menu navigates and activates items" {
    const items = [_]Menu.Item{
        .{ .label = "CLI", .detail = "single-binary terminal app" },
        .{ .label = "CLI + WASM", .detail = "shared core across hosts" },
    };

    var menu = Menu.init(&items);
    try std.testing.expect(menu.update(.down));
    try std.testing.expectEqual(@as(usize, 1), menu.selected);
    try std.testing.expect(menu.shouldActivate(.enter));
    try std.testing.expect(menu.shouldActivate(.{ .character = ' ' }));
}

test "menu composes detail text" {
    const items = [_]Menu.Item{
        .{ .label = "CLI", .detail = "single-binary terminal app" },
    };

    var tree = ui.Tree.init(std.testing.allocator);
    defer tree.deinit();

    const menu = Menu.init(&items);
    const root = try menu.compose(&tree);
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    try tree.render(buffer.writer(std.testing.allocator), root, .{ .ansi = false });
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "CLI") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "single-binary terminal app") != null);
}
