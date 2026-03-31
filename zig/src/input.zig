const std = @import("std");

pub const Key = union(enum) {
    character: u21,
    up,
    down,
    left,
    right,
    enter,
    escape,
    backspace,
    tab,
    ctrl_c,
    ctrl_z,
    unknown: u8,

    pub fn isCharacter(self: Key, ch: u21) bool {
        return switch (self) {
            .character => |value| value == ch,
            else => false,
        };
    }

    pub fn name(self: Key, buffer: *[16]u8) []const u8 {
        return switch (self) {
            .character => |value| std.unicode.utf8Encode(value, buffer) catch "<?>",
            .up => "up",
            .down => "down",
            .left => "left",
            .right => "right",
            .enter => "enter",
            .escape => "escape",
            .backspace => "backspace",
            .tab => "tab",
            .ctrl_c => "ctrl+c",
            .ctrl_z => "ctrl+z",
            .unknown => "unknown",
        };
    }
};

pub fn parse(bytes: []const u8) ?Key {
    if (bytes.len == 0) return null;

    return switch (bytes[0]) {
        0x03 => .ctrl_c,
        0x1A => .ctrl_z,
        '\r', '\n' => .enter,
        '\t' => .tab,
        0x7F => .backspace,
        0x1B => parseEscape(bytes),
        else => parsePrintable(bytes),
    };
}

fn parseEscape(bytes: []const u8) Key {
    if (bytes.len >= 3 and bytes[1] == '[') {
        return switch (bytes[2]) {
            'A' => .up,
            'B' => .down,
            'C' => .right,
            'D' => .left,
            else => .escape,
        };
    }
    return .escape;
}

fn parsePrintable(bytes: []const u8) Key {
    const first = bytes[0];
    if (first >= 0x20 and first < 0x7F) {
        return .{ .character = first };
    }

    const sequence_len = std.unicode.utf8ByteSequenceLength(first) catch {
        return .{ .unknown = first };
    };
    if (bytes.len < sequence_len) {
        return .{ .unknown = first };
    }

    const codepoint = std.unicode.utf8Decode(bytes[0..sequence_len]) catch {
        return .{ .unknown = first };
    };
    return .{ .character = codepoint };
}

test "parses arrow keys and ascii" {
    try std.testing.expectEqualDeep(Key.up, parse("\x1b[A").?);
    try std.testing.expectEqualDeep(Key.down, parse("\x1b[B").?);
    try std.testing.expect(parse("q").?.isCharacter('q'));
}
