const std = @import("std");
const HeadlessProgram = @import("../headless.zig").HeadlessProgram;
const tea = @import("../tea.zig");
const FocusRing = @import("../focus.zig").FocusRing;
const ui = @import("../ui.zig");
const Badge = @import("../components/badge.zig").Badge;
const Form = @import("../components/form.zig").Form;
const ProgressBar = @import("../components/progress.zig").ProgressBar;
const Spinner = @import("../components/spinner.zig").Spinner;
const List = @import("../components/list.zig").List;
const TextInput = @import("../components/text_input.zig").TextInput;
const Table = @import("../components/table.zig").Table;

// The showcase uses one text input to filter a small rewrite roadmap.
const FilterInput = TextInput(64);
// The draft form demonstrates multi-field focus and editing on top of the
// shared text-input primitive.
const DraftForm = Form(3, 48);

const empty_items = [_][]const u8{};
const roadmap_headers = [_][]const u8{ "Status", "Area", "Notes" };
const row_runtime = [_][]const u8{ "Done", "Runtime", "headless core + terminal host" };
const row_tree = [_][]const u8{ "Done", "UI tree", "composable boxes, rows, columns, and tones" };
const row_input = [_][]const u8{ "In Progress", "Input", "stateful decoder, split utf8, CSI navigation, more still to port" };
const row_components = [_][]const u8{ "In Progress", "Components", "list, progress, text input, table, and form are now native Zig widgets" };
const row_browser = [_][]const u8{ "Next", "Browser host", "reuse the same model tree through WASM with a real web renderer" };
const roadmap_rows = [_][]const []const u8{
    &row_runtime,
    &row_tree,
    &row_input,
    &row_components,
    &row_browser,
};

const draft_fields = [_]DraftForm.FieldSpec{
    .{ .id = "name", .label = "Name", .placeholder = "bubbletea-zig-admin", .tone = .accent },
    .{ .id = "command", .label = "Command", .placeholder = "zig build run", .tone = .success },
    .{ .id = "target", .label = "Target", .placeholder = "cli + wasm", .tone = .warning },
};

const zone_filter: usize = 0;
const zone_list: usize = 1;
const zone_form: usize = 2;

/// Shared demo app rendered by the terminal host and the WASM host.
pub fn App(comptime Msg: type) type {
    return struct {
        spinner: Spinner = Spinner.init(1),
        filter: FilterInput = FilterInput.init(.{
            .prompt = "filter> ",
            .placeholder = "type to narrow the rewrite surface",
            .tone = .accent,
            .focused = true,
        }),
        list: List = List.init(&empty_items),
        draft: DraftForm = DraftForm.init(draft_fields, .{
            .help = "tab/shift+tab moves between fields inside the form",
            .tone = .warning,
            .active = false,
        }),
        focus: FocusRing = FocusRing.init(3),
        visible_labels: [roadmap_rows.len][]const u8 = undefined,
        visible_rows: [roadmap_rows.len][]const []const u8 = undefined,
        visible_len: usize = 0,
        size: tea.Size = .{},
        terminal_focused: bool = true,

        const Self = @This();

        /// Seeds derived state and starts the spinner timer.
        pub fn init(self: *Self) ?tea.Cmd(Msg) {
            self.rebuildVisible();
            self.syncFocus();
            return self.spinner.tick(Msg);
        }

        /// Handles outer focus switching, field editing, list navigation,
        /// resize messages, and spinner ticks.
        pub fn update(self: *Self, msg: Msg) !tea.Update(Msg) {
            switch (msg) {
                .key => |key| {
                    if (key == .ctrl_c) return tea.Update(Msg).quitNow();
                    if (key.isCharacter('q')) return tea.Update(Msg).quitNow();

                    if (key == .page_up or key == .page_down) {
                        if (self.focus.update(key)) {
                            self.syncFocus();
                            return .{};
                        }
                    }

                    switch (self.focus.current() orelse zone_filter) {
                        zone_filter => {
                            // Filter edits immediately rebuild the derived list
                            // and table views.
                            if (self.filter.update(key)) {
                                self.rebuildVisible();
                                return .{};
                            }
                            return tea.Update(Msg).noop();
                        },
                        zone_list => {
                            if (self.list.update(key)) {
                                return .{};
                            }
                            return tea.Update(Msg).noop();
                        },
                        zone_form => {
                            if (self.draft.update(key)) {
                                return .{};
                            }
                            return tea.Update(Msg).noop();
                        },
                        else => return tea.Update(Msg).noop(),
                    }
                },
                .paste => |text| {
                    switch (self.focus.current() orelse zone_filter) {
                        zone_filter => {
                            if (self.filter.insertText(text)) {
                                self.rebuildVisible();
                                return .{};
                            }
                            return tea.Update(Msg).noop();
                        },
                        zone_form => {
                            if (self.draft.paste(text)) {
                                return .{};
                            }
                            return tea.Update(Msg).noop();
                        },
                        else => return tea.Update(Msg).noop(),
                    }
                },
                .focus_gained => {
                    if (self.terminal_focused) return tea.Update(Msg).noop();
                    self.terminal_focused = true;
                    return .{};
                },
                .focus_lost => {
                    if (!self.terminal_focused) return tea.Update(Msg).noop();
                    self.terminal_focused = false;
                    return .{};
                },
                .mouse => |mouse| {
                    if ((self.focus.current() orelse zone_filter) == zone_list and self.list.updateMouse(mouse)) {
                        return .{};
                    }
                    return tea.Update(Msg).noop();
                },
                .resize => |size| {
                    // Resize state is currently informational, but later layout
                    // work can consume it directly.
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

        /// Composes the entire dashboard as a single view tree.
        pub fn compose(self: *const Self, tree: *ui.Tree) !ui.NodeId {
            const header_title = try tree.textStyled("bubbletea-zig", .{ .tone = .accent });
            const header_subtitle = try tree.textStyled(
                "rewrite in progress: richer input, editable state, composable widgets",
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
            const focus_label = try tree.textStyled(
                try std.fmt.allocPrint(tree.allocator(), "panel: {s}", .{focusLabel(self.focus.current() orelse zone_filter)}),
                .{ .tone = .warning },
            );
            const size = try tree.textStyled(
                try std.fmt.allocPrint(tree.allocator(), "size: {d}x{d}", .{ self.size.width, self.size.height }),
                .{ .tone = .muted },
            );
            const host_focus = try tree.textStyled(
                if (self.terminal_focused) "tty: focused" else "tty: blurred",
                .{ .tone = if (self.terminal_focused) .success else .warning },
            );
            const status_rule = try tree.rule(10, .{ .tone = .muted });
            const status = try tree.box(
                try tree.row(&.{ spinner, status_label, status_rule, focus_label, size, host_focus }, .{ .gap = 2 }),
                .{
                    .title = "Runtime",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = .success,
                },
            );

            const progress = ProgressBar{
                .current = doneCount(),
                .total = roadmap_rows.len,
                .width = 20,
                .tone = .accent,
            };
            const progress_label = try tree.textStyled("rewrite momentum", .{ .tone = .muted });
            const visible_count = try tree.textStyled(
                try std.fmt.allocPrint(tree.allocator(), "{d}/{d} rows visible", .{ self.visible_len, roadmap_rows.len }),
                .{ .tone = .muted },
            );
            const progress_panel = try tree.box(
                try tree.row(&.{ progress_label, try progress.compose(tree), visible_count }, .{ .gap = 2 }),
                .{
                    .title = "Progress",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = .warning,
                },
            );

            const filter_panel = try tree.box(
                try self.filter.compose(tree),
                .{
                    .title = if (self.focus.isFocused(zone_filter)) "Filter (focused)" else "Filter",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = if (self.focus.isFocused(zone_filter)) .accent else .muted,
                },
            );

            const list_panel = try tree.box(
                try self.list.compose(tree),
                .{
                    .title = if (self.focus.isFocused(zone_list)) "Visible Areas (focused)" else "Visible Areas",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = if (self.focus.isFocused(zone_list)) .success else .accent,
                },
            );

            const table = Table{
                .headers = &roadmap_headers,
                .rows = self.visibleRows(),
                .selected_row = if (self.visible_len == 0) null else self.list.selected,
                .selected_tone = .success,
            };
            const board_panel = try tree.box(
                try table.compose(tree),
                .{
                    .title = "Rewrite Board",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = .warning,
                },
            );

            const draft_panel = try tree.box(
                try self.draft.compose(tree),
                .{
                    .title = if (self.focus.isFocused(zone_form)) "Draft App (focused)" else "Draft App",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = if (self.focus.isFocused(zone_form)) .warning else .muted,
                },
            );

            const selected = self.selectedRow();
            const selection_badge = try Badge.init(selectedStatus(selected), toneForStatus(selectedStatus(selected))).compose(tree);
            const selection_area = try tree.textStyled(selectedArea(selected), .{ .tone = .accent });
            const selection_note = try tree.textStyled(selectedNote(selected), .{ .tone = .muted });
            const selection_panel = try tree.box(
                try tree.column(&.{ selection_badge, selection_area, selection_note }, .{ .gap = 1 }),
                .{
                    .title = "Selection",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = .success,
                },
            );

            const preview_lines = try tree.allocNodeIds(3);
            preview_lines[0] = try tree.textStyled(
                try std.fmt.allocPrint(tree.allocator(), "name: {s}", .{displayValue(self.draft.valueById("name"), "bubbletea-zig-admin")}),
                .{ .tone = .accent },
            );
            preview_lines[1] = try tree.textStyled(
                try std.fmt.allocPrint(tree.allocator(), "command: {s}", .{displayValue(self.draft.valueById("command"), "zig build run")}),
                .{ .tone = .success },
            );
            preview_lines[2] = try tree.textStyled(
                try std.fmt.allocPrint(tree.allocator(), "target: {s}", .{displayValue(self.draft.valueById("target"), "cli + wasm")}),
                .{ .tone = .warning },
            );
            const preview_panel = try tree.box(
                try tree.column(preview_lines, .{ .gap = 0 }),
                .{
                    .title = "Scaffold Preview",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = .accent,
                },
            );

            const controls = try tree.box(
                try tree.textStyled(
                    "page-up/page-down switch panels, paste goes into focused inputs, mouse wheel scrolls the list, q quits",
                    .{ .tone = .muted },
                ),
                .{
                    .title = "Controls",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = .muted,
                },
            );

            return tree.column(
                &.{ header, status, progress_panel, filter_panel, list_panel, board_panel, draft_panel, preview_panel, selection_panel, controls },
                .{ .gap = 1 },
            );
        }

        // Rebuilds the visible list and table rows from the current filter.
        fn rebuildVisible(self: *Self) void {
            const query = self.filter.value();
            var count: usize = 0;

            for (roadmap_rows) |row| {
                if (!matchesRow(row, query)) continue;
                self.visible_rows[count] = row;
                self.visible_labels[count] = row[1];
                count += 1;
            }

            self.visible_len = count;
            self.list.setItems(self.visible_labels[0..count]);
        }

        // Synchronizes child focus state after outer panel changes.
        fn syncFocus(self: *Self) void {
            self.filter.setFocused(self.focus.isFocused(zone_filter));
            self.draft.setActive(self.focus.isFocused(zone_form));
        }

        // Returns only the currently visible roadmap rows.
        fn visibleRows(self: *const Self) []const []const []const u8 {
            return self.visible_rows[0..self.visible_len];
        }

        // Returns the selected filtered row, if one exists.
        fn selectedRow(self: *const Self) ?[]const []const u8 {
            if (self.visible_len == 0) return null;
            return self.visible_rows[self.list.selected];
        }
    };
}

// Counts finished rows to drive the progress bar.
fn doneCount() usize {
    var count: usize = 0;
    for (roadmap_rows) |row| {
        if (std.mem.eql(u8, row[0], "Done")) count += 1;
    }
    return count;
}

// Extracts the selected row status for the summary panel.
fn selectedStatus(row: ?[]const []const u8) []const u8 {
    if (row) |value| return value[0];
    return "Empty";
}

// Extracts the selected row area label for the summary panel.
fn selectedArea(row: ?[]const []const u8) []const u8 {
    if (row) |value| return value[1];
    return "no visible results";
}

// Extracts the selected row note for the summary panel.
fn selectedNote(row: ?[]const []const u8) []const u8 {
    if (row) |value| return value[2];
    return "adjust the filter or keep typing into the focused panel";
}

// Maps status labels back to semantic tones.
fn toneForStatus(status: []const u8) ui.Tone {
    if (std.mem.eql(u8, status, "Done")) return .success;
    if (std.mem.eql(u8, status, "In Progress")) return .warning;
    if (std.mem.eql(u8, status, "Next")) return .accent;
    return .muted;
}

// Formats a panel label for the current outer focus target.
fn focusLabel(index: usize) []const u8 {
    return switch (index) {
        zone_filter => "filter",
        zone_list => "list",
        zone_form => "form",
        else => "unknown",
    };
}

// Uses placeholder text when a field has not been filled yet.
fn displayValue(value: ?[]const u8, fallback: []const u8) []const u8 {
    const resolved = value orelse return fallback;
    if (resolved.len == 0) return fallback;
    return resolved;
}

// Any matching cell keeps the row visible.
fn matchesRow(row: []const []const u8, query: []const u8) bool {
    if (query.len == 0) return true;
    for (row) |cell| {
        if (containsAsciiCaseInsensitive(cell, query)) return true;
    }
    return false;
}

// The showcase only needs ASCII-insensitive matching for now.
fn containsAsciiCaseInsensitive(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;

    var start: usize = 0;
    while (start + needle.len <= haystack.len) : (start += 1) {
        var matched = true;
        for (needle, 0..) |needle_byte, index| {
            const haystack_byte = haystack[start + index];
            if (std.ascii.toLower(haystack_byte) != std.ascii.toLower(needle_byte)) {
                matched = false;
                break;
            }
        }
        if (matched) return true;
    }

    return false;
}

test "showcase routes outer focus into the draft form" {
    const Msg = tea.Message(void);
    const ShowcaseApp = App(Msg);

    var program = HeadlessProgram(ShowcaseApp, void).init(std.testing.allocator, .{});
    defer program.deinit();

    try std.testing.expect(!(try program.drain()));
    try std.testing.expect(program.model.focus.isFocused(zone_filter));

    try program.send(.{ .key = .page_down });
    try program.send(.{ .key = .page_down });
    try std.testing.expect(!(try program.drain()));
    try std.testing.expect(program.model.focus.isFocused(zone_form));

    try program.send(.{ .key = .{ .character = 'd' } });
    try program.send(.{ .key = .{ .character = 'e' } });
    try program.send(.{ .key = .{ .character = 'm' } });
    try program.send(.{ .key = .{ .character = 'o' } });
    try program.send(.{ .key = .tab });
    try program.send(.{ .key = .{ .character = 'c' } });
    try program.send(.{ .key = .{ .character = 'm' } });
    try program.send(.{ .key = .{ .character = 'd' } });
    try std.testing.expect(!(try program.drain()));

    try std.testing.expectEqualStrings("demo", program.model.draft.valueById("name").?);
    try std.testing.expectEqualStrings("cmd", program.model.draft.valueById("command").?);
}

test "showcase accepts paste and focus events" {
    const Msg = tea.Message(void);
    const ShowcaseApp = App(Msg);

    var program = HeadlessProgram(ShowcaseApp, void).init(std.testing.allocator, .{});
    defer program.deinit();

    try std.testing.expect(!(try program.drain()));
    try program.send(.{ .paste = "input" });
    try std.testing.expect(!(try program.drain()));
    try std.testing.expectEqualStrings("input", program.model.filter.value());

    try program.send(.focus_lost);
    try std.testing.expect(!(try program.drain()));
    try std.testing.expect(!program.model.terminal_focused);

    try program.send(.{ .key = .page_down });
    try program.send(.{ .key = .page_down });
    try program.send(.{ .paste = "zig-app" });
    try std.testing.expect(!(try program.drain()));
    try std.testing.expectEqualStrings("zig-app", program.model.draft.valueById("name").?);

    try program.send(.focus_gained);
    try std.testing.expect(!(try program.drain()));
    try std.testing.expect(program.model.terminal_focused);
}

test "showcase list reacts to mouse wheel when focused" {
    const Msg = tea.Message(void);
    const ShowcaseApp = App(Msg);

    var program = HeadlessProgram(ShowcaseApp, void).init(std.testing.allocator, .{});
    defer program.deinit();

    try std.testing.expect(!(try program.drain()));
    try program.send(.{ .key = .page_down });
    try std.testing.expect(!(try program.drain()));
    try std.testing.expect(program.model.focus.isFocused(zone_list));

    try program.send(.{ .mouse = .{
        .x = 0,
        .y = 0,
        .button = .wheel_down,
        .action = .scroll,
    } });
    try std.testing.expect(!(try program.drain()));
    try std.testing.expectEqual(@as(usize, 1), program.model.list.selected);
}
