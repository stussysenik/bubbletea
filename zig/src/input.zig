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

/// Mouse buttons normalized from SGR reporting.
pub const MouseButton = enum {
    none,
    left,
    middle,
    right,
    wheel_up,
    wheel_down,
    wheel_left,
    wheel_right,
};

/// Mouse actions normalized from terminal escape sequences.
pub const MouseAction = enum {
    press,
    release,
    drag,
    move,
    scroll,
};

/// Keyboard modifiers attached to terminal mouse events.
pub const MouseModifiers = struct {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
};

/// Mouse position and metadata as reported by the terminal host.
pub const MouseEvent = struct {
    x: u16,
    y: u16,
    button: MouseButton,
    action: MouseAction,
    modifiers: MouseModifiers = .{},
};

/// Higher-level input event emitted by the decoder.
pub const Event = union(enum) {
    key: Key,
    paste: []const u8,
    focus_gained,
    focus_lost,
    mouse: MouseEvent,
};

/// Buffered decoder that can absorb partial reads and emit one logical event
/// at a time.
pub const Decoder = struct {
    allocator: std.mem.Allocator,
    pending: std.ArrayList(u8) = .empty,
    in_paste: bool = false,
    ready_paste_len: ?usize = null,

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

    /// Returns the next decoded event when enough bytes are buffered.
    ///
    /// Paste payload slices remain valid until the next decoder mutation call.
    pub fn nextEvent(self: *Decoder) ?Event {
        self.finishReadyPaste();

        while (true) {
            if (self.in_paste) {
                if (std.mem.indexOf(u8, self.pending.items, paste_end_sequence)) |index| {
                    self.in_paste = false;
                    self.ready_paste_len = index;
                    return .{ .paste = self.pending.items[0..index] };
                }
                return null;
            }

            switch (parseOne(self.pending.items)) {
                .none, .pending => return null,
                .item => |decoded| {
                    self.consume(decoded.consumed);
                    switch (decoded.value) {
                        .event => |event| return event,
                        .paste_start => {
                            self.in_paste = true;
                            continue;
                        },
                    }
                },
            }
        }
    }

    /// Forces any partial non-paste sequence to resolve when the host has
    /// gone idle.
    pub fn flushEvent(self: *Decoder) ?Event {
        self.finishReadyPaste();

        while (true) {
            if (self.in_paste) {
                if (std.mem.indexOf(u8, self.pending.items, paste_end_sequence)) |index| {
                    self.in_paste = false;
                    self.ready_paste_len = index;
                    return .{ .paste = self.pending.items[0..index] };
                }
                return null;
            }

            if (self.pending.items.len == 0) return null;

            switch (parseOne(self.pending.items)) {
                .none => return null,
                .item => |decoded| {
                    self.consume(decoded.consumed);
                    switch (decoded.value) {
                        .event => |event| return event,
                        .paste_start => {
                            self.in_paste = true;
                            continue;
                        },
                    }
                },
                .pending => {
                    const first = self.pending.items[0];
                    const event: Event = switch (first) {
                        0x1B => .{ .key = .escape },
                        else => .{ .key = .{ .unknown = first } },
                    };

                    if (first == 0x1B and self.pending.items.len > 1 and (self.pending.items[1] == '[' or self.pending.items[1] == 'O')) {
                        self.pending.clearRetainingCapacity();
                    } else {
                        self.consume(1);
                    }

                    return event;
                },
            }
        }
    }

    /// Compatibility helper for legacy key-only callers.
    pub fn next(self: *Decoder) ?Key {
        while (self.nextEvent()) |event| {
            switch (event) {
                .key => |key| return key,
                else => continue,
            }
        }
        return null;
    }

    /// Compatibility helper for legacy key-only callers.
    pub fn flush(self: *Decoder) ?Key {
        const event = self.flushEvent() orelse return null;
        return switch (event) {
            .key => |key| key,
            else => null,
        };
    }

    /// Reports whether undecoded bytes or an open paste block are buffered.
    pub fn hasPending(self: *const Decoder) bool {
        return self.pending.items.len != 0 or self.in_paste or self.ready_paste_len != null;
    }

    // Removes bytes whose paste payload was already handed to the caller.
    fn finishReadyPaste(self: *Decoder) void {
        const payload_len = self.ready_paste_len orelse return;
        self.consume(payload_len + paste_end_sequence.len);
        self.ready_paste_len = null;
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
        .item => |decoded| switch (decoded.value) {
            .event => |event| switch (event) {
                .key => |key| key,
                else => null,
            },
            .paste_start => null,
        },
        .none, .pending => null,
    };
}

// Internal result for a single decode attempt.
const DecodedItem = struct {
    value: ParsedItem,
    consumed: usize,
};

// Parser-level token used before the runtime turns it into a message.
const ParsedItem = union(enum) {
    event: Event,
    paste_start,
};

// Distinguishes between "no data", "need more bytes", and "decoded item".
const DecodeState = union(enum) {
    none,
    pending,
    item: DecodedItem,
};

// Decodes the first logical token available in a byte slice.
fn parseOne(bytes: []const u8) DecodeState {
    if (bytes.len == 0) return .none;

    return switch (bytes[0]) {
        0x03 => .{ .item = .{ .value = .{ .event = .{ .key = .ctrl_c } }, .consumed = 1 } },
        0x1A => .{ .item = .{ .value = .{ .event = .{ .key = .ctrl_z } }, .consumed = 1 } },
        '\r', '\n' => .{ .item = .{ .value = .{ .event = .{ .key = .enter } }, .consumed = 1 } },
        '\t' => .{ .item = .{ .value = .{ .event = .{ .key = .tab } }, .consumed = 1 } },
        0x7F => .{ .item = .{ .value = .{ .event = .{ .key = .backspace } }, .consumed = 1 } },
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
        else => .{ .item = .{ .value = .{ .event = .{ .key = .escape } }, .consumed = 1 } },
    };
}

// Parses CSI sequences such as arrows, home/end, mouse, focus, and paste.
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
        'A' => keyItem(.up, consumed),
        'B' => keyItem(.down, consumed),
        'C' => keyItem(.right, consumed),
        'D' => keyItem(.left, consumed),
        'F' => keyItem(.end, consumed),
        'H' => keyItem(.home, consumed),
        'I' => .{ .item = .{ .value = .{ .event = .focus_gained }, .consumed = consumed } },
        'O' => .{ .item = .{ .value = .{ .event = .focus_lost }, .consumed = consumed } },
        'Z' => keyItem(.shift_tab, consumed),
        'M', 'm' => parseCsiMouse(params, final, consumed),
        '~' => parseCsiTilde(params, consumed),
        else => keyItem(.{ .unknown = final }, consumed),
    };
}

// Handles `CSI <n> ~` style navigation keys and bracketed paste markers.
fn parseCsiTilde(params: []const u8, consumed: usize) DecodeState {
    const primary = parsePrimaryParam(params) orelse {
        return keyItem(.{ .unknown = '~' }, consumed);
    };

    return switch (primary) {
        1, 7 => keyItem(.home, consumed),
        3 => keyItem(.delete, consumed),
        4, 8 => keyItem(.end, consumed),
        5 => keyItem(.page_up, consumed),
        6 => keyItem(.page_down, consumed),
        200 => .{ .item = .{ .value = .paste_start, .consumed = consumed } },
        else => keyItem(.{ .unknown = '~' }, consumed),
    };
}

// Parses SGR mouse reporting of the form `CSI <Cb;Cx;Cy M` or `m`.
fn parseCsiMouse(params: []const u8, final: u8, consumed: usize) DecodeState {
    if (params.len == 0 or params[0] != '<') {
        return keyItem(.{ .unknown = final }, consumed);
    }

    var parts = std.mem.splitScalar(u8, params[1..], ';');
    const code_text = parts.next() orelse return keyItem(.{ .unknown = final }, consumed);
    const x_text = parts.next() orelse return keyItem(.{ .unknown = final }, consumed);
    const y_text = parts.next() orelse return keyItem(.{ .unknown = final }, consumed);

    const code = std.fmt.parseInt(u16, code_text, 10) catch return keyItem(.{ .unknown = final }, consumed);
    const x = std.fmt.parseInt(u16, x_text, 10) catch return keyItem(.{ .unknown = final }, consumed);
    const y = std.fmt.parseInt(u16, y_text, 10) catch return keyItem(.{ .unknown = final }, consumed);

    const modifiers: MouseModifiers = .{
        .shift = (code & 4) != 0,
        .alt = (code & 8) != 0,
        .ctrl = (code & 16) != 0,
    };
    const button_code = code & 3;
    const is_motion = (code & 32) != 0;
    const is_wheel = (code & 64) != 0;

    var event = MouseEvent{
        .x = if (x > 0) x - 1 else 0,
        .y = if (y > 0) y - 1 else 0,
        .button = .none,
        .action = .press,
        .modifiers = modifiers,
    };

    if (is_wheel) {
        event.action = .scroll;
        event.button = switch (button_code) {
            0 => .wheel_up,
            1 => .wheel_down,
            2 => .wheel_left,
            3 => .wheel_right,
            else => .none,
        };
    } else if (final == 'm') {
        event.action = .release;
        event.button = decodePointerButton(button_code);
    } else if (is_motion) {
        event.action = if (button_code == 3) .move else .drag;
        event.button = decodePointerButton(button_code);
    } else {
        event.action = .press;
        event.button = decodePointerButton(button_code);
    }

    return .{
        .item = .{
            .value = .{ .event = .{ .mouse = event } },
            .consumed = consumed,
        },
    };
}

// Handles SS3 cursor-key sequences emitted by some terminals.
fn parseSs3(bytes: []const u8) DecodeState {
    if (bytes.len < 3) return .pending;

    return switch (bytes[2]) {
        'A' => keyItem(.up, 3),
        'B' => keyItem(.down, 3),
        'C' => keyItem(.right, 3),
        'D' => keyItem(.left, 3),
        'F' => keyItem(.end, 3),
        'H' => keyItem(.home, 3),
        else => |value| keyItem(.{ .unknown = value }, 3),
    };
}

// Parses printable ASCII or a full UTF-8 codepoint.
fn parsePrintable(bytes: []const u8) DecodeState {
    const first = bytes[0];
    if (first >= 0x20 and first < 0x7F) {
        return keyItem(.{ .character = first }, 1);
    }

    const sequence_len = std.unicode.utf8ByteSequenceLength(first) catch {
        return keyItem(.{ .unknown = first }, 1);
    };
    if (bytes.len < sequence_len) return .pending;

    const codepoint = std.unicode.utf8Decode(bytes[0..sequence_len]) catch {
        return keyItem(.{ .unknown = first }, 1);
    };

    return keyItem(.{ .character = codepoint }, sequence_len);
}

// Creates a decode item for key events.
fn keyItem(key: Key, consumed: usize) DecodeState {
    return .{
        .item = .{
            .value = .{ .event = .{ .key = key } },
            .consumed = consumed,
        },
    };
}

// Pointer-button decoding for SGR mouse reports.
fn decodePointerButton(code: u16) MouseButton {
    return switch (code) {
        0 => .left,
        1 => .middle,
        2 => .right,
        else => .none,
    };
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

// Terminal control sequence that ends bracketed paste mode payloads.
const paste_end_sequence = "\x1b[201~";

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

test "decoder emits focus events" {
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();

    try decoder.feed("\x1b[I\x1b[O");
    try std.testing.expectEqualDeep(Event.focus_gained, decoder.nextEvent().?);
    try std.testing.expectEqualDeep(Event.focus_lost, decoder.nextEvent().?);
    try std.testing.expect(decoder.nextEvent() == null);
}

test "decoder buffers bracketed paste until terminator" {
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();

    try decoder.feed("\x1b[200~bubble");
    try std.testing.expect(decoder.nextEvent() == null);
    try decoder.feed("tea-zig\x1b[201~");

    const event = decoder.nextEvent().?;
    switch (event) {
        .paste => |text| try std.testing.expectEqualStrings("bubbletea-zig", text),
        else => return error.UnexpectedEvent,
    }

    try std.testing.expect(decoder.nextEvent() == null);
}

test "decoder parses sgr mouse press and scroll events" {
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();

    try decoder.feed("\x1b[<0;5;7M\x1b[<65;5;8M");

    const press = decoder.nextEvent().?;
    switch (press) {
        .mouse => |mouse| {
            try std.testing.expectEqual(MouseAction.press, mouse.action);
            try std.testing.expectEqual(MouseButton.left, mouse.button);
            try std.testing.expectEqual(@as(u16, 4), mouse.x);
            try std.testing.expectEqual(@as(u16, 6), mouse.y);
        },
        else => return error.UnexpectedEvent,
    }

    const scroll = decoder.nextEvent().?;
    switch (scroll) {
        .mouse => |mouse| {
            try std.testing.expectEqual(MouseAction.scroll, mouse.action);
            try std.testing.expectEqual(MouseButton.wheel_down, mouse.button);
            try std.testing.expectEqual(@as(u16, 4), mouse.x);
            try std.testing.expectEqual(@as(u16, 7), mouse.y);
        },
        else => return error.UnexpectedEvent,
    }
}
