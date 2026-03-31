const std = @import("std");

/// Normalized key values used by the runtime and components.
pub const Key = union(enum) {
    character: u21,
    up,
    down,
    left,
    right,
    home,
    end,
    delete,
    page_up,
    page_down,
    enter,
    escape,
    backspace,
    tab,
    shift_tab,
    ctrl_c,
    ctrl_z,
    unknown: u8,

    /// Returns true when the key is a specific Unicode scalar.
    pub fn isCharacter(self: Key, ch: u21) bool {
        return switch (self) {
            .character => |value| value == ch,
            else => false,
        };
    }

    /// Formats a key name for debug output and diagnostics.
    pub fn name(self: Key, buffer: *[16]u8) []const u8 {
        return switch (self) {
            .character => |value| std.unicode.utf8Encode(value, buffer) catch "<?>",
            .up => "up",
            .down => "down",
            .left => "left",
            .right => "right",
            .home => "home",
            .end => "end",
            .delete => "delete",
            .page_up => "page-up",
            .page_down => "page-down",
            .enter => "enter",
            .escape => "escape",
            .backspace => "backspace",
            .tab => "tab",
            .shift_tab => "shift+tab",
            .ctrl_c => "ctrl+c",
            .ctrl_z => "ctrl+z",
            .unknown => "unknown",
        };
    }
};

/// Buffered decoder that can absorb partial reads and emit one logical key at
/// a time.
pub const Decoder = struct {
    allocator: std.mem.Allocator,
    pending: std.ArrayList(u8) = .empty,

    pub fn init(allocator: std.mem.Allocator) Decoder {
        return .{ .allocator = allocator };
    }

    /// Releases buffered undecoded bytes.
    pub fn deinit(self: *Decoder) void {
        self.pending.deinit(self.allocator);
    }

    /// Appends raw terminal bytes to the decoder buffer.
    pub fn feed(self: *Decoder, bytes: []const u8) !void {
        try self.pending.appendSlice(self.allocator, bytes);
    }

    /// Returns the next decoded key when enough bytes are buffered.
    pub fn next(self: *Decoder) ?Key {
        switch (parseOne(self.pending.items)) {
            .none, .pending => return null,
            .key => |decoded| {
                self.consume(decoded.consumed);
                return decoded.value;
            },
        }
    }

    /// Forces any partial sequence to resolve as a standalone key when the
    /// host has gone idle.
    pub fn flush(self: *Decoder) ?Key {
        if (self.pending.items.len == 0) return null;

        switch (parseOne(self.pending.items)) {
            .none => return null,
            .key => |decoded| {
                self.consume(decoded.consumed);
                return decoded.value;
            },
            .pending => {
                const first = self.pending.items[0];
                const key: Key = switch (first) {
                    0x1B => .escape,
                    else => .{ .unknown = first },
                };

                if (first == 0x1B and self.pending.items.len > 1 and (self.pending.items[1] == '[' or self.pending.items[1] == 'O')) {
                    self.pending.clearRetainingCapacity();
                } else {
                    self.consume(1);
                }

                return key;
            },
        }
    }

    /// Reports whether undecoded bytes are still buffered.
    pub fn hasPending(self: *const Decoder) bool {
        return self.pending.items.len != 0;
    }

    // Removes decoded bytes while keeping the backing allocation.
    fn consume(self: *Decoder, count: usize) void {
        if (count == 0) return;
        if (count >= self.pending.items.len) {
            self.pending.clearRetainingCapacity();
            return;
        }

        const remaining = self.pending.items.len - count;
        std.mem.copyForwards(u8, self.pending.items[0..remaining], self.pending.items[count..]);
        self.pending.items.len = remaining;
    }
};

/// Convenience one-shot parser used by tests and simple callers.
pub fn parse(bytes: []const u8) ?Key {
    return switch (parseOne(bytes)) {
        .key => |decoded| decoded.value,
        .none, .pending => null,
    };
}

// Internal result for a single decode attempt.
const DecodedKey = struct {
    value: Key,
    consumed: usize,
};

// Distinguishes between "no data", "need more bytes", and "decoded key".
const DecodeState = union(enum) {
    none,
    pending,
    key: DecodedKey,
};

// Decodes the first logical key available in a byte slice.
fn parseOne(bytes: []const u8) DecodeState {
    if (bytes.len == 0) return .none;

    return switch (bytes[0]) {
        0x03 => .{ .key = .{ .value = .ctrl_c, .consumed = 1 } },
        0x1A => .{ .key = .{ .value = .ctrl_z, .consumed = 1 } },
        '\r', '\n' => .{ .key = .{ .value = .enter, .consumed = 1 } },
        '\t' => .{ .key = .{ .value = .tab, .consumed = 1 } },
        0x7F => .{ .key = .{ .value = .backspace, .consumed = 1 } },
        0x1B => parseEscape(bytes),
        else => parsePrintable(bytes),
    };
}

// Escape sequences need incremental parsing because terminal reads can split
// them across multiple polls.
fn parseEscape(bytes: []const u8) DecodeState {
    if (bytes.len == 1) return .pending;

    return switch (bytes[1]) {
        '[' => parseCsi(bytes),
        'O' => parseSs3(bytes),
        else => .{ .key = .{ .value = .escape, .consumed = 1 } },
    };
}

// Parses CSI sequences such as arrows, home/end, and delete.
fn parseCsi(bytes: []const u8) DecodeState {
    if (bytes.len < 3) return .pending;

    const tail = bytes[2..];
    var final_index: usize = 0;
    while (final_index < tail.len and !isFinalByte(tail[final_index])) : (final_index += 1) {}
    if (final_index >= tail.len) return .pending;

    const final = tail[final_index];
    const params = tail[0..final_index];
    const consumed = 2 + final_index + 1;

    return switch (final) {
        'A' => .{ .key = .{ .value = .up, .consumed = consumed } },
        'B' => .{ .key = .{ .value = .down, .consumed = consumed } },
        'C' => .{ .key = .{ .value = .right, .consumed = consumed } },
        'D' => .{ .key = .{ .value = .left, .consumed = consumed } },
        'F' => .{ .key = .{ .value = .end, .consumed = consumed } },
        'H' => .{ .key = .{ .value = .home, .consumed = consumed } },
        'Z' => .{ .key = .{ .value = .shift_tab, .consumed = consumed } },
        '~' => parseCsiTilde(params, consumed),
        else => .{ .key = .{ .value = .{ .unknown = final }, .consumed = consumed } },
    };
}

// Handles `CSI <n> ~` style navigation keys.
fn parseCsiTilde(params: []const u8, consumed: usize) DecodeState {
    const primary = parsePrimaryParam(params) orelse {
        return .{ .key = .{ .value = .{ .unknown = '~' }, .consumed = consumed } };
    };

    const key: Key = switch (primary) {
        1, 7 => .home,
        3 => .delete,
        4, 8 => .end,
        5 => .page_up,
        6 => .page_down,
        else => .{ .unknown = '~' },
    };

    return .{ .key = .{ .value = key, .consumed = consumed } };
}

// Handles SS3 cursor-key sequences emitted by some terminals.
fn parseSs3(bytes: []const u8) DecodeState {
    if (bytes.len < 3) return .pending;

    return switch (bytes[2]) {
        'A' => .{ .key = .{ .value = .up, .consumed = 3 } },
        'B' => .{ .key = .{ .value = .down, .consumed = 3 } },
        'C' => .{ .key = .{ .value = .right, .consumed = 3 } },
        'D' => .{ .key = .{ .value = .left, .consumed = 3 } },
        'F' => .{ .key = .{ .value = .end, .consumed = 3 } },
        'H' => .{ .key = .{ .value = .home, .consumed = 3 } },
        else => |value| .{ .key = .{ .value = .{ .unknown = value }, .consumed = 3 } },
    };
}

// Parses printable ASCII or a full UTF-8 codepoint.
fn parsePrintable(bytes: []const u8) DecodeState {
    const first = bytes[0];
    if (first >= 0x20 and first < 0x7F) {
        return .{ .key = .{ .value = .{ .character = first }, .consumed = 1 } };
    }

    const sequence_len = std.unicode.utf8ByteSequenceLength(first) catch {
        return .{ .key = .{ .value = .{ .unknown = first }, .consumed = 1 } };
    };
    if (bytes.len < sequence_len) return .pending;

    const codepoint = std.unicode.utf8Decode(bytes[0..sequence_len]) catch {
        return .{ .key = .{ .value = .{ .unknown = first }, .consumed = 1 } };
    };

    return .{ .key = .{ .value = .{ .character = codepoint }, .consumed = sequence_len } };
}

// Only the first numeric parameter is currently needed for navigation keys.
fn parsePrimaryParam(params: []const u8) ?usize {
    if (params.len == 0) return 1;

    var value: usize = 0;
    var saw_digit = false;
    for (params) |byte| {
        if (byte == ';' or byte == ':') break;
        if (!std.ascii.isDigit(byte)) return null;
        saw_digit = true;
        value = value * 10 + (byte - '0');
    }

    if (!saw_digit) return null;
    return value;
}

// ANSI final bytes terminate a CSI sequence.
fn isFinalByte(byte: u8) bool {
    return byte >= 0x40 and byte <= 0x7E;
}

test "parses navigation keys and ascii" {
    try std.testing.expectEqualDeep(Key.up, parse("\x1b[A").?);
    try std.testing.expectEqualDeep(Key.down, parse("\x1b[B").?);
    try std.testing.expectEqualDeep(Key.home, parse("\x1b[H").?);
    try std.testing.expectEqualDeep(Key.end, parse("\x1b[F").?);
    try std.testing.expectEqualDeep(Key.delete, parse("\x1b[3~").?);
    try std.testing.expectEqualDeep(Key.page_down, parse("\x1b[6~").?);
    try std.testing.expectEqualDeep(Key.shift_tab, parse("\x1b[Z").?);
    try std.testing.expect(parse("q").?.isCharacter('q'));
}

test "decoder drains multiple keys from one read" {
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();

    try decoder.feed("jk");
    try std.testing.expect(decoder.next().?.isCharacter('j'));
    try std.testing.expect(decoder.next().?.isCharacter('k'));
    try std.testing.expect(decoder.next() == null);
}

test "decoder buffers partial escape sequences" {
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();

    try decoder.feed("\x1b");
    try std.testing.expect(decoder.next() == null);
    try decoder.feed("[A");
    try std.testing.expectEqualDeep(Key.up, decoder.next().?);
    try std.testing.expect(decoder.next() == null);
}

test "decoder flushes standalone escape" {
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();

    try decoder.feed("\x1b");
    try std.testing.expect(decoder.next() == null);
    try std.testing.expectEqualDeep(Key.escape, decoder.flush().?);
}

test "decoder buffers split utf8" {
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();

    const e_acute = [_]u8{ 0xC3, 0xA9 };
    try decoder.feed(e_acute[0..1]);
    try std.testing.expect(decoder.next() == null);
    try decoder.feed(e_acute[1..2]);
    try std.testing.expect(decoder.next().?.isCharacter('é'));
}
