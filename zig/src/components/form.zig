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
        };

        /// Shared presentation options for the form container.
        pub const Options = struct {
            title: ?[]const u8 = null,
            help: ?[]const u8 = null,
            tone: ui.Tone = .accent,
            active: bool = true,
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
                try writer.writeByte('\n');
            }
        }

        /// Composes the form into labeled field panels and optional help text.
        pub fn compose(self: *const Self, tree: *ui.Tree) !ui.NodeId {
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
            const nodes = try tree.allocNodeIds(field_count + extra);
            var count: usize = 0;

            inline for (0..field_count) |index| {
                const spec = self.specs[index];
                const focused = self.active and self.focus.isFocused(index);

                const id_badge = try tree.textStyled(spec.id, .{ .tone = .muted });
                const field_box = try tree.box(
                    try self.inputs[index].compose(tree),
                    .{
                        .title = spec.label,
                        .padding = ui.Insets.symmetric(0, 1),
                        .tone = if (focused) spec.tone else .muted,
                    },
                );

                nodes[count] = try tree.column(&.{ id_badge, field_box }, .{ .gap = 0 });
                count += 1;
            }

            if (self.help) |help| {
                nodes[count] = try tree.textStyled(help, .{ .tone = .muted });
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

    try std.testing.expect(form.update(.{ .character = 'a' }));
    try std.testing.expectEqualStrings("a", form.value(0));
    try std.testing.expect(form.update(.tab));
    try std.testing.expect(form.update(.{ .character = 'b' }));
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

test "form pastes into the focused field" {
    const DemoForm = Form(2, 32);
    var form = DemoForm.init(.{
        .{ .id = "name", .label = "Name" },
        .{ .id = "cmd", .label = "Command" },
    }, .{});

    try std.testing.expect(form.paste("zig"));
    try std.testing.expectEqualStrings("zig", form.valueById("name").?);
    try std.testing.expect(form.update(.tab));
    try std.testing.expect(form.paste("build run"));
    try std.testing.expectEqualStrings("build run", form.valueById("cmd").?);
}
