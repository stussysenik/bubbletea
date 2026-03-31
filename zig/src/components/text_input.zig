const std = @import("std");
const tea = @import("../tea.zig");
const ui = @import("../ui.zig");

/// Fixed-capacity UTF-8 text input that keeps editing logic allocation-free in
/// the hot path.
pub fn TextInput(comptime capacity: usize) type {
    return struct {
        // The buffer stores UTF-8 bytes while `cursor` and `len` are byte
        // offsets aligned to codepoint boundaries.
        buffer: [capacity]u8 = [_]u8{0} ** capacity,
        len: usize = 0,
        cursor: usize = 0,
        prompt: []const u8 = "> ",
        placeholder: []const u8 = "",
        tone: ui.Tone = .accent,
        focused: bool = true,

        const Self = @This();

        /// Construction options for prompt, placeholder, and focus state.
        pub const Options = struct {
            prompt: []const u8 = "> ",
            placeholder: []const u8 = "",
            tone: ui.Tone = .accent,
            focused: bool = true,
        };

        /// Creates an empty text input with the requested presentation options.
        pub fn init(options: Options) Self {
            return .{
                .prompt = options.prompt,
                .placeholder = options.placeholder,
                .tone = options.tone,
                .focused = options.focused,
            };
        }

        /// Returns the active value as a UTF-8 slice.
        pub fn value(self: *const Self) []const u8 {
            return self.buffer[0..self.len];
        }

        /// Toggles whether the input should render an active cursor.
        pub fn setFocused(self: *Self, focused: bool) void {
            self.focused = focused;
        }

        /// Resets the field to an empty string.
        pub fn clear(self: *Self) void {
            self.len = 0;
            self.cursor = 0;
        }

        /// Replaces the current value with a caller-provided UTF-8 slice.
        pub fn setValue(self: *Self, text: []const u8) !void {
            if (text.len > capacity) return error.NoSpaceLeft;
            @memcpy(self.buffer[0..text.len], text);
            self.len = text.len;
            self.cursor = text.len;
        }

        /// Inserts an entire UTF-8 slice at the current cursor location.
        pub fn insertText(self: *Self, text: []const u8) bool {
            if (text.len == 0) return false;
            if (self.len + text.len > capacity) return false;

            // Validation happens before mutation so paste-style inserts stay
            // all-or-nothing.
            var index: usize = 0;
            while (index < text.len) {
                const sequence_len = std.unicode.utf8ByteSequenceLength(text[index]) catch return false;
                if (index + sequence_len > text.len) return false;
                _ = std.unicode.utf8Decode(text[index .. index + sequence_len]) catch return false;
                index += sequence_len;
            }

            std.mem.copyBackwards(
                u8,
                self.buffer[self.cursor + text.len .. self.len + text.len],
                self.buffer[self.cursor..self.len],
            );
            std.mem.copyForwards(
                u8,
                self.buffer[self.cursor .. self.cursor + text.len],
                text,
            );

            self.len += text.len;
            self.cursor += text.len;
            return true;
        }

        /// Applies editing and cursor-motion keys.
        pub fn update(self: *Self, key: tea.Key) bool {
            return switch (key) {
                .character => |codepoint| self.insertCodepoint(codepoint),
                .backspace => self.backspace(),
                .delete => self.deleteForward(),
                .left => self.moveLeft(),
                .right => self.moveRight(),
                .home => blk: {
                    if (self.cursor == 0) break :blk false;
                    self.cursor = 0;
                    break :blk true;
                },
                .end => blk: {
                    if (self.cursor == self.len) break :blk false;
                    self.cursor = self.len;
                    break :blk true;
                },
                else => false,
            };
        }

        /// Plain text fallback with a visible `|` cursor marker.
        pub fn view(self: *const Self, writer: anytype) !void {
            try writer.writeAll(self.prompt);
            if (!self.focused) {
                if (self.len == 0) {
                    try writer.writeAll(self.placeholder);
                } else {
                    try writer.writeAll(self.value());
                }
                return;
            }

            try writer.writeAll(self.value()[0..self.cursor]);
            try writer.writeByte('|');
            if (self.cursor < self.len) {
                try writer.writeAll(self.value()[self.cursor..]);
            } else if (self.len == 0 and self.placeholder.len > 0) {
                try writer.writeAll(self.placeholder);
            }
        }

        /// Composes the prompt, text, and cursor into tree nodes.
        pub fn compose(self: *const Self, tree: *ui.Tree) !ui.NodeId {
            var nodes: [4]ui.NodeId = undefined;
            var count: usize = 0;

            if (self.prompt.len > 0) {
                nodes[count] = try tree.textStyled(self.prompt, .{ .tone = .muted });
                count += 1;
            }

            if (!self.focused) {
                if (self.len == 0 and self.placeholder.len > 0) {
                    nodes[count] = try tree.textStyled(self.placeholder, .{ .tone = .muted });
                    count += 1;
                } else {
                    nodes[count] = try tree.text(self.value());
                    count += 1;
                }
            } else {
                if (self.cursor > 0) {
                    nodes[count] = try tree.text(self.value()[0..self.cursor]);
                    count += 1;
                }

                nodes[count] = try tree.cursor(self.tone);
                count += 1;

                if (self.cursor < self.len) {
                    nodes[count] = try tree.text(self.value()[self.cursor..]);
                    count += 1;
                } else if (self.len == 0 and self.placeholder.len > 0) {
                    nodes[count] = try tree.textStyled(self.placeholder, .{ .tone = .muted });
                    count += 1;
                }
            }

            if (count == 0) {
                nodes[count] = try tree.text("");
                count += 1;
            }

            return tree.row(nodes[0..count], .{ .gap = 0 });
        }

        // Inserts a codepoint at the cursor and shifts the remaining bytes.
        fn insertCodepoint(self: *Self, codepoint: u21) bool {
            var encoded: [4]u8 = undefined;
            const encoded_len = std.unicode.utf8Encode(codepoint, &encoded) catch return false;
            if (self.len + encoded_len > capacity) return false;

            std.mem.copyBackwards(
                u8,
                self.buffer[self.cursor + encoded_len .. self.len + encoded_len],
                self.buffer[self.cursor..self.len],
            );
            std.mem.copyForwards(
                u8,
                self.buffer[self.cursor .. self.cursor + encoded_len],
                encoded[0..encoded_len],
            );

            self.len += encoded_len;
            self.cursor += encoded_len;
            return true;
        }

        // Removes the codepoint immediately to the left of the cursor.
        fn backspace(self: *Self) bool {
            if (self.cursor == 0) return false;
            const start = previousBoundary(self.value(), self.cursor);
            self.deleteRange(start, self.cursor);
            self.cursor = start;
            return true;
        }

        // Removes the codepoint at the cursor position.
        fn deleteForward(self: *Self) bool {
            if (self.cursor >= self.len) return false;
            const end = nextBoundary(self.value(), self.cursor);
            self.deleteRange(self.cursor, end);
            return true;
        }

        // Moves one Unicode scalar to the left.
        fn moveLeft(self: *Self) bool {
            if (self.cursor == 0) return false;
            self.cursor = previousBoundary(self.value(), self.cursor);
            return true;
        }

        // Moves one Unicode scalar to the right.
        fn moveRight(self: *Self) bool {
            if (self.cursor >= self.len) return false;
            self.cursor = nextBoundary(self.value(), self.cursor);
            return true;
        }

        // Compacts a deleted byte range in-place.
        fn deleteRange(self: *Self, start: usize, end: usize) void {
            if (start >= end or end > self.len) return;

            const remove_len = end - start;
            std.mem.copyForwards(
                u8,
                self.buffer[start .. self.len - remove_len],
                self.buffer[end..self.len],
            );
            self.len -= remove_len;
        }
    };
}

// Walks backwards to the start of the previous UTF-8 scalar.
fn previousBoundary(bytes: []const u8, cursor: usize) usize {
    if (cursor == 0) return 0;

    var index = cursor - 1;
    while (index > 0 and isContinuationByte(bytes[index])) : (index -= 1) {}
    return index;
}

// Advances to the next UTF-8 scalar boundary.
fn nextBoundary(bytes: []const u8, cursor: usize) usize {
    if (cursor >= bytes.len) return bytes.len;

    const sequence_len = std.unicode.utf8ByteSequenceLength(bytes[cursor]) catch 1;
    return @min(cursor + sequence_len, bytes.len);
}

// UTF-8 continuation bytes always carry the `10xxxxxx` prefix.
fn isContinuationByte(byte: u8) bool {
    return (byte & 0xC0) == 0x80;
}

test "text input inserts navigates and deletes utf8 content" {
    var input = TextInput(32).init(.{
        .prompt = "filter> ",
        .placeholder = "search",
    });

    try std.testing.expect(input.update(.{ .character = 'z' }));
    try std.testing.expect(input.update(.{ .character = 'i' }));
    try std.testing.expect(input.update(.{ .character = 'g' }));
    try std.testing.expectEqualStrings("zig", input.value());

    try std.testing.expect(input.update(.left));
    try std.testing.expect(input.update(.{ .character = '!' }));
    try std.testing.expectEqualStrings("zi!g", input.value());

    try std.testing.expect(input.update(.backspace));
    try std.testing.expectEqualStrings("zig", input.value());

    try std.testing.expect(input.update(.home));
    try std.testing.expect(input.update(.{ .character = 'é' }));
    try std.testing.expectEqualStrings("ézig", input.value());

    try std.testing.expect(input.update(.delete));
    try std.testing.expectEqualStrings("éig", input.value());
}

test "text input compose shows prompt cursor and placeholder" {
    var tree = ui.Tree.init(std.testing.allocator);
    defer tree.deinit();

    const input = TextInput(16).init(.{
        .prompt = "query> ",
        .placeholder = "type here",
    });

    const root = try input.compose(&tree);
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    try tree.render(buffer.writer(std.testing.allocator), root, .{ .ansi = false });
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "query> ") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "|") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "type here") != null);
}

test "text input can paste a utf8 slice" {
    var input = TextInput(32).init(.{
        .prompt = "draft> ",
    });

    try std.testing.expect(input.insertText("zig "));
    try std.testing.expect(input.insertText("téa"));
    try std.testing.expectEqualStrings("zig téa", input.value());
}
