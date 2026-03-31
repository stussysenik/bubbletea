const std = @import("std");
const tea = @import("../tea.zig");
const ui = @import("../ui.zig");
const FocusRing = @import("../focus.zig").FocusRing;
const TextInput = @import("text_input.zig").TextInput;

/// Reusable labeled form built from a fixed number of text inputs.
pub fn Form(comptime field_count: usize, comptime capacity: usize) type {
    const Input = TextInput(capacity);

    return struct {
        specs: [field_count]FieldSpec,
        inputs: [field_count]Input,
        focus: FocusRing = FocusRing.init(field_count),
        active: bool = true,
        title: ?[]const u8 = null,
        help: ?[]const u8 = null,
        tone: ui.Tone = .accent,

        const Self = @This();

        /// Metadata used to build one labeled field.
        pub const FieldSpec = struct {
            id: []const u8,
            label: []const u8,
            placeholder: []const u8 = "",
            prompt: []const u8 = "",
            tone: ui.Tone = .accent,
            required: bool = false,
            min_len: usize = 0,
        };

        /// Shared presentation options for the form container.
        pub const Options = struct {
            title: ?[]const u8 = null,
            help: ?[]const u8 = null,
            tone: ui.Tone = .accent,
            active: bool = true,
        };

        /// Optional composition metadata for hosts that want direct field
        /// targeting instead of replaying keyboard focus moves.
        pub const ComposeOptions = struct {
            field_action_kind: ?[]const u8 = null,
        };

        /// Creates a form from caller-provided field definitions.
        pub fn init(specs: [field_count]FieldSpec, options: Options) Self {
            var inputs: [field_count]Input = undefined;
            inline for (specs, 0..) |spec, index| {
                inputs[index] = Input.init(.{
                    .prompt = spec.prompt,
                    .placeholder = spec.placeholder,
                    .tone = spec.tone,
                    .focused = options.active and index == 0,
                });
            }

            return .{
                .specs = specs,
                .inputs = inputs,
                .focus = FocusRing.init(field_count),
                .active = options.active,
                .title = options.title,
                .help = options.help,
                .tone = options.tone,
            };
        }

        /// Returns the value of a field by index.
        pub fn value(self: *const Self, index: usize) []const u8 {
            return self.inputs[index].value();
        }

        /// Returns the value of a field identified by `id`.
        pub fn valueById(self: *const Self, id: []const u8) ?[]const u8 {
            for (self.specs, 0..) |spec, index| {
                if (std.mem.eql(u8, spec.id, id)) {
                    return self.inputs[index].value();
                }
            }
            return null;
        }

        /// Returns a mutable pointer to a field input.
        pub fn field(self: *Self, index: usize) *Input {
            return &self.inputs[index];
        }

        /// Enables or disables active cursor rendering for the form.
        pub fn setActive(self: *Self, active: bool) void {
            self.active = active;
            self.syncFocus();
        }

        /// Focuses an explicit field index.
        pub fn setFocusedIndex(self: *Self, index: usize) bool {
            if (!self.focus.focus(index)) return false;
            self.syncFocus();
            return true;
        }

        /// Handles form-level focus keys and field editing keys.
        pub fn update(self: *Self, key: tea.Key) bool {
            if (self.focus.update(key)) {
                self.syncFocus();
                return true;
            }

            const index = self.focus.current() orelse return false;
            return self.inputs[index].update(key);
        }

        /// Inserts pasted UTF-8 text into the currently focused field.
        pub fn paste(self: *Self, text: []const u8) bool {
            const index = self.focus.current() orelse return false;
            return self.inputs[index].insertText(text);
        }

        /// Returns true when every field satisfies its declarative rules.
        pub fn isValid(self: *const Self) bool {
            return self.firstInvalidIndex() == null;
        }

        /// Counts how many fields currently fail validation.
        pub fn invalidCount(self: *const Self) usize {
            var count: usize = 0;
            inline for (0..field_count) |index| {
                if (self.validationMessage(index) != null) count += 1;
            }
            return count;
        }

        /// Returns the first invalid field index when validation fails.
        pub fn firstInvalidIndex(self: *const Self) ?usize {
            inline for (0..field_count) |index| {
                if (self.validationMessage(index) != null) return index;
            }
            return null;
        }

        /// Focuses the first invalid field to help callers guide correction.
        pub fn focusFirstInvalid(self: *Self) bool {
            const index = self.firstInvalidIndex() orelse return false;
            return self.setFocusedIndex(index);
        }

        /// Returns the validation message for one field when it is invalid.
        pub fn validationMessage(self: *const Self, index: usize) ?[]const u8 {
            const spec = self.specs[index];
            const field_value = self.inputs[index].value();
            if (spec.required and field_value.len == 0) {
                return "required";
            }
            if (spec.min_len > 0 and field_value.len < spec.min_len) {
                return "too short";
            }
            return null;
        }

        /// Plain text fallback for headless or minimal hosts.
        pub fn view(self: *const Self, writer: anytype) !void {
            if (field_count == 0) {
                try writer.writeAll("(empty form)\n");
                return;
            }

            for (self.specs, 0..) |spec, index| {
                const marker = if (self.active and self.focus.isFocused(index)) ">" else " ";
                try std.fmt.format(writer, "{s} {s}: ", .{ marker, spec.label });
                try self.inputs[index].view(writer);
                if (self.validationMessage(index)) |message| {
                    try std.fmt.format(writer, " [{s}]", .{message});
                }
                try writer.writeByte('\n');
            }
        }

        /// Composes the form into labeled field panels and optional help text.
        pub fn compose(self: *const Self, tree: *ui.Tree) !ui.NodeId {
            return self.composeWithOptions(tree, .{});
        }

        /// Composes the form and optionally tags each field for direct host
        /// actions such as browser-side field focusing.
        pub fn composeWithOptions(self: *const Self, tree: *ui.Tree, options: ComposeOptions) !ui.NodeId {
            if (field_count == 0) {
                const empty = try tree.textStyled("(empty form)", .{ .tone = .muted });
                return if (self.title) |title|
                    tree.box(empty, .{
                        .title = title,
                        .padding = ui.Insets.symmetric(0, 1),
                        .tone = self.tone,
                    })
                else
                    empty;
            }

            const extra: usize = if (self.help != null) 1 else 0;
            const summary_extra: usize = if (self.invalidCount() != 0) 1 else 0;
            const nodes = try tree.allocNodeIds(field_count + extra + summary_extra);
            var count: usize = 0;

            inline for (0..field_count) |index| {
                const spec = self.specs[index];
                const focused = self.active and self.focus.isFocused(index);
                const validation = self.validationMessage(index);

                const id_badge = try tree.textStyled(spec.id, .{ .tone = .muted });
                const field_box = try tree.box(
                    try self.inputs[index].compose(tree),
                    .{
                        .title = spec.label,
                        .action = if (options.field_action_kind) |action_kind|
                            .{
                                .kind = action_kind,
                                .value = index,
                            }
                        else
                            null,
                        .padding = ui.Insets.symmetric(0, 1),
                        .tone = if (validation != null) .warning else if (focused) spec.tone else .muted,
                    },
                );

                if (validation) |message| {
                    nodes[count] = try tree.column(
                        &.{
                            id_badge,
                            field_box,
                            try tree.textStyled(message, .{ .tone = .warning }),
                        },
                        .{ .gap = 0 },
                    );
                } else {
                    nodes[count] = try tree.column(&.{ id_badge, field_box }, .{ .gap = 0 });
                }
                count += 1;
            }

            if (self.help) |help| {
                nodes[count] = try tree.textStyled(help, .{ .tone = .muted });
                count += 1;
            }

            if (self.invalidCount() != 0) {
                nodes[count] = try tree.textStyled(
                    try std.fmt.allocPrint(tree.allocator(), "{d} field(s) need attention", .{self.invalidCount()}),
                    .{ .tone = .warning },
                );
                count += 1;
            }

            const body = try tree.column(nodes[0..count], .{ .gap = 1 });
            return if (self.title) |title|
                tree.box(body, .{
                    .title = title,
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = self.tone,
                })
            else
                body;
        }

        // Synchronizes the active cursor state after form-level focus changes.
        fn syncFocus(self: *Self) void {
            inline for (0..field_count) |index| {
                self.inputs[index].setFocused(self.active and self.focus.isFocused(index));
            }
        }
    };
}

test "form cycles focus and edits fields" {
    const DemoForm = Form(2, 32);
    var form = DemoForm.init(.{
        .{ .id = "name", .label = "Name", .placeholder = "bubbletea-zig" },
        .{ .id = "cmd", .label = "Command", .placeholder = "zig build run" },
    }, .{
        .title = "Draft",
        .help = "tab moves between fields",
    });

    try std.testing.expect(form.update(tea.Key.character('a')));
    try std.testing.expectEqualStrings("a", form.value(0));
    try std.testing.expect(form.update(tea.Key.tab));
    try std.testing.expect(form.update(tea.Key.character('b')));
    try std.testing.expectEqualStrings("b", form.valueById("cmd").?);
}

test "form compose includes labels and help text" {
    const DemoForm = Form(1, 32);
    var form = DemoForm.init(.{
        .{ .id = "name", .label = "Name", .placeholder = "bubbletea-zig" },
    }, .{
        .title = "Draft App",
        .help = "tab moves between fields",
    });

    var tree = ui.Tree.init(std.testing.allocator);
    defer tree.deinit();

    const root = try form.compose(&tree);
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    try tree.render(buffer.writer(std.testing.allocator), root, .{ .ansi = false });
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "Draft App") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "Name") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "tab moves between fields") != null);
}

test "form can compose browser action metadata per field" {
    const DemoForm = Form(2, 32);
    const form = DemoForm.init(.{
        .{ .id = "name", .label = "Name" },
        .{ .id = "cmd", .label = "Command" },
    }, .{});

    var tree = ui.Tree.init(std.testing.allocator);
    defer tree.deinit();

    const root = try form.composeWithOptions(&tree, .{ .field_action_kind = "form_field" });
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    try tree.writeJson(buffer.writer(std.testing.allocator), root);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"action\":{\"kind\":\"form_field\",\"value\":0}") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"action\":{\"kind\":\"form_field\",\"value\":1}") != null);
}

test "form pastes into the focused field" {
    const DemoForm = Form(2, 32);
    var form = DemoForm.init(.{
        .{ .id = "name", .label = "Name" },
        .{ .id = "cmd", .label = "Command" },
    }, .{});

    try std.testing.expect(form.paste("zig"));
    try std.testing.expectEqualStrings("zig", form.valueById("name").?);
    try std.testing.expect(form.update(tea.Key.tab));
    try std.testing.expect(form.paste("build run"));
    try std.testing.expectEqualStrings("build run", form.valueById("cmd").?);
}

test "form validation tracks missing and short fields" {
    const DemoForm = Form(2, 32);
    var form = DemoForm.init(.{
        .{ .id = "name", .label = "Name", .required = true },
        .{ .id = "cmd", .label = "Command", .min_len = 3 },
    }, .{});

    try std.testing.expect(!form.isValid());
    try std.testing.expectEqual(@as(usize, 2), form.invalidCount());
    try std.testing.expectEqualStrings("required", form.validationMessage(0).?);
    try std.testing.expectEqualStrings("too short", form.validationMessage(1).?);

    try std.testing.expect(form.paste("zig"));
    try std.testing.expect(form.update(tea.Key.tab));
    try std.testing.expect(form.paste("run"));
    try std.testing.expect(form.isValid());
    try std.testing.expectEqual(@as(usize, 0), form.invalidCount());
}
