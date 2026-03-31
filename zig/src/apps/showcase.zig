const std = @import("std");
const tea = @import("../tea.zig");
const ui = @import("../ui.zig");
const Badge = @import("../components/badge.zig").Badge;
const ProgressBar = @import("../components/progress.zig").ProgressBar;
const Spinner = @import("../components/spinner.zig").Spinner;
const List = @import("../components/list.zig").List;

pub const items = [_][]const u8{
    "Runtime: headless-first core for CLI and GUI hosts",
    "Renderer: terminal diffing now, browser/WASM host next",
    "Components: composable spinner and list in plain Zig",
    "Scope: use Lua only for optional scripting, not the core loop",
};

pub fn App(comptime Msg: type) type {
    return struct {
        spinner: Spinner = Spinner.init(1),
        list: List = List.init(&items),
        size: tea.Size = .{},

        const Self = @This();

        pub fn init(self: *Self) ?tea.Cmd(Msg) {
            return self.spinner.tick(Msg);
        }

        pub fn update(self: *Self, msg: Msg) !tea.Update(Msg) {
            switch (msg) {
                .key => |key| {
                    if (key == .ctrl_c) return tea.Update(Msg).quitNow();
                    if (key.isCharacter('q')) return tea.Update(Msg).quitNow();

                    if (key.isCharacter('j')) {
                        _ = self.list.update(.down);
                        return .{};
                    }
                    if (key.isCharacter('k')) {
                        _ = self.list.update(.up);
                        return .{};
                    }

                    if (self.list.update(key)) {
                        return .{};
                    }

                    return tea.Update(Msg).noop();
                },
                .resize => |size| {
                    self.size = size;
                    return .{};
                },
                .timer => {
                    if (self.spinner.update(Msg, msg)) |command| {
                        return tea.Update(Msg).withCommand(command);
                    }
                    return tea.Update(Msg).noop();
                },
                else => return tea.Update(Msg).noop(),
            }
        }

        pub fn compose(self: *const Self, tree: *ui.Tree) !ui.NodeId {
            const header_title = try tree.textStyled("bubbletea-zig", .{ .tone = .accent });
            const header_subtitle = try tree.textStyled(
                "composable CLI framework with headless and WASM hosts",
                .{ .tone = .muted },
            );
            const badge_cli = try Badge.init("CLI", .accent).compose(tree);
            const badge_headless = try Badge.init("HEADLESS", .success).compose(tree);
            const badge_wasm = try Badge.init("WASM", .warning).compose(tree);
            const header_badges = try tree.row(&.{ badge_cli, badge_headless, badge_wasm }, .{ .gap = 1 });
            const header = try tree.box(
                try tree.column(&.{ header_title, header_subtitle, header_badges }, .{ .gap = 1 }),
                .{
                    .title = "Framework",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = .accent,
                },
            );

            const spinner = try self.spinner.compose(tree);
            const status_label = try tree.textStyled("one model, multiple hosts", .{ .tone = .success });
            const size = try tree.textStyled(
                try std.fmt.allocPrint(tree.allocator(), "size: {d}x{d}", .{ self.size.width, self.size.height }),
                .{ .tone = .muted },
            );
            const status_rule = try tree.rule(18, .{ .tone = .muted });
            const status = try tree.box(
                try tree.row(&.{ spinner, status_label, status_rule, size }, .{ .gap = 2 }),
                .{
                    .title = "Runtime",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = .success,
                },
            );

            const progress = ProgressBar{
                .current = self.list.selected + 1,
                .total = self.list.items.len,
                .width = 20,
                .tone = .accent,
            };
            const progress_label = try tree.textStyled("rewrite momentum", .{ .tone = .muted });
            const progress_panel = try tree.box(
                try tree.row(&.{ progress_label, try progress.compose(tree) }, .{ .gap = 2 }),
                .{
                    .title = "Progress",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = .warning,
                },
            );

            const list_panel = try tree.box(
                try self.list.compose(tree),
                .{
                    .title = "CLI Building Blocks",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = .accent,
                },
            );

            const selected_text = try tree.textStyled(
                try std.fmt.allocPrint(tree.allocator(), "selected: {s}", .{self.list.selectedItem() orelse "none"}),
                .{ .tone = .success },
            );
            const selection_panel = try tree.box(
                selected_text,
                .{
                    .title = "Selection",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = .success,
                },
            );

            const controls = try tree.box(
                try tree.textStyled("up/down or j/k to move, q or ctrl+c to quit", .{ .tone = .muted }),
                .{
                    .title = "Controls",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = .muted,
                },
            );

            return tree.column(
                &.{ header, status, progress_panel, list_panel, selection_panel, controls },
                .{ .gap = 1 },
            );
        }
    };
}
