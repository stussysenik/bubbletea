const std = @import("std");

/// Keyboard modifiers normalized from terminal protocols such as CSI `u`.
pub const KeyModifiers = packed struct(u8) {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
    super: bool = false,
    hyper: bool = false,
    meta: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,

    /// Returns true when any modifier bit is active.
    pub fn any(self: KeyModifiers) bool {
        return self.shift or self.alt or self.ctrl or self.super or self.hyper or self.meta or self.caps_lock or self.num_lock;
    }

    /// Returns true when only the provided modifier mask is active.
    pub fn eql(self: KeyModifiers, other: KeyModifiers) bool {
        return @as(u8, @bitCast(self)) == @as(u8, @bitCast(other));
    }
};

/// Optional key lifecycle metadata exposed by richer keyboard protocols.
pub const KeyEventKind = enum {
    press,
    repeat,
    release,
};

/// Normalized key values used by the runtime and components.
pub const Key = struct {
    code: Code,
    text: u21 = 0,
    raw: u32 = 0,
    modifiers: KeyModifiers = .{},
    event: KeyEventKind = .press,

    /// Named key variants shared by terminal and browser hosts.
    pub const Code = enum {
        character,
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
        insert,
        ctrl_c,
        ctrl_z,
        unknown,
    };

    pub const up: Key = .{ .code = .up };
    pub const down: Key = .{ .code = .down };
    pub const left: Key = .{ .code = .left };
    pub const right: Key = .{ .code = .right };
    pub const home: Key = .{ .code = .home };
    pub const end: Key = .{ .code = .end };
    pub const delete: Key = .{ .code = .delete };
    pub const page_up: Key = .{ .code = .page_up };
    pub const page_down: Key = .{ .code = .page_down };
    pub const enter: Key = .{ .code = .enter };
    pub const escape: Key = .{ .code = .escape };
    pub const backspace: Key = .{ .code = .backspace };
    pub const tab: Key = .{ .code = .tab };
    pub const shift_tab: Key = .{ .code = .shift_tab };
    pub const insert: Key = .{ .code = .insert };
    pub const ctrl_c: Key = .{ .code = .ctrl_c };
    pub const ctrl_z: Key = .{ .code = .ctrl_z };

    /// Creates a plain Unicode keypress.
    pub fn character(value: u21) Key {
        return .{
            .code = .character,
            .text = value,
        };
    }

    /// Creates a Unicode keypress that carries protocol-level modifiers.
    pub fn characterWithModifiers(value: u21, modifiers: KeyModifiers) Key {
        return .{
            .code = .character,
            .text = value,
            .modifiers = modifiers,
        };
    }

    /// Creates an unknown key token that preserves the raw protocol value.
    pub fn unknown(value: u32) Key {
        return .{
            .code = .unknown,
            .raw = value,
        };
    }

    /// Returns a copy of the key with updated modifiers.
    pub fn withModifiers(self: Key, modifiers: KeyModifiers) Key {
        var next = self;
        next.modifiers = modifiers;
        return next;
    }

    /// Returns a copy of the key with updated press/repeat/release metadata.
    pub fn withEvent(self: Key, event: KeyEventKind) Key {
        var next = self;
        next.event = event;
        return next;
    }

    /// Returns true when the key is an unmodified press of a specific code.
    pub fn isCode(self: Key, code: Code) bool {
        return self.code == code and self.event == .press and !self.modifiers.any();
    }

    /// Returns true when the key is a specific Unicode scalar.
    pub fn isCharacter(self: Key, ch: u21) bool {
        return self.code == .character and self.text == ch and self.event == .press and !self.modifiers.any();
    }

    /// Returns true when the key is a Unicode scalar with exact modifiers.
    pub fn isCharacterWithModifiers(self: Key, ch: u21, modifiers: KeyModifiers) bool {
        return self.code == .character and self.text == ch and self.event == .press and self.modifiers.eql(modifiers);
    }

    /// Returns true when the key matches another normalized key exactly.
    pub fn eql(self: Key, other: Key) bool {
        return self.code == other.code and self.text == other.text and self.raw == other.raw and self.modifiers.eql(other.modifiers) and self.event == other.event;
    }

    /// Formats a key name for debug output and diagnostics.
    pub fn name(self: Key, buffer: *[48]u8) []const u8 {
        var stream = std.io.fixedBufferStream(buffer);
        const writer = stream.writer();

        if (self.modifiers.shift) writer.writeAll("shift+") catch return "<?>"; 
        if (self.modifiers.alt) writer.writeAll("alt+") catch return "<?>"; 
        if (self.modifiers.ctrl) writer.writeAll("ctrl+") catch return "<?>"; 
        if (self.modifiers.super) writer.writeAll("super+") catch return "<?>"; 
        if (self.modifiers.hyper) writer.writeAll("hyper+") catch return "<?>"; 
        if (self.modifiers.meta) writer.writeAll("meta+") catch return "<?>"; 

        switch (self.code) {
            .character => {
                var encoded: [4]u8 = undefined;
                const text = std.unicode.utf8Encode(self.text, &encoded) catch return "<?>"; 
                writer.writeAll(encoded[0..text]) catch return "<?>"; 
            },
            .up => writer.writeAll("up") catch return "<?>",
            .down => writer.writeAll("down") catch return "<?>",
            .left => writer.writeAll("left") catch return "<?>",
            .right => writer.writeAll("right") catch return "<?>",
            .home => writer.writeAll("home") catch return "<?>",
            .end => writer.writeAll("end") catch return "<?>",
            .delete => writer.writeAll("delete") catch return "<?>",
            .page_up => writer.writeAll("page-up") catch return "<?>",
            .page_down => writer.writeAll("page-down") catch return "<?>",
            .enter => writer.writeAll("enter") catch return "<?>",
            .escape => writer.writeAll("escape") catch return "<?>",
            .backspace => writer.writeAll("backspace") catch return "<?>",
            .tab => writer.writeAll("tab") catch return "<?>",
            .shift_tab => writer.writeAll("shift+tab") catch return "<?>",
            .insert => writer.writeAll("insert") catch return "<?>",
            .ctrl_c => writer.writeAll("ctrl+c") catch return "<?>",
            .ctrl_z => writer.writeAll("ctrl+z") catch return "<?>",
            .unknown => std.fmt.format(writer, "unknown({d})", .{self.raw}) catch return "<?>",
        }

        switch (self.event) {
            .press => {},
            .repeat => writer.writeAll(" (repeat)") catch return "<?>",
            .release => writer.writeAll(" (release)") catch return "<?>",
        }
        return stream.getWritten();
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
                        0x1B => .{ .key = Key.escape },
                        else => .{ .key = Key.unknown(first) },
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
        0x03 => .{ .item = .{ .value = .{ .event = .{ .key = Key.ctrl_c } }, .consumed = 1 } },
        0x1A => .{ .item = .{ .value = .{ .event = .{ .key = Key.ctrl_z } }, .consumed = 1 } },
        '\r', '\n' => .{ .item = .{ .value = .{ .event = .{ .key = Key.enter } }, .consumed = 1 } },
        '\t' => .{ .item = .{ .value = .{ .event = .{ .key = Key.tab } }, .consumed = 1 } },
        0x7F => .{ .item = .{ .value = .{ .event = .{ .key = Key.backspace } }, .consumed = 1 } },
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
        else => .{ .item = .{ .value = .{ .event = .{ .key = Key.escape } }, .consumed = 1 } },
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
        'A' => parseCsiNamedKey(params, consumed, Key.up),
        'B' => parseCsiNamedKey(params, consumed, Key.down),
        'C' => parseCsiNamedKey(params, consumed, Key.right),
        'D' => parseCsiNamedKey(params, consumed, Key.left),
        'F' => parseCsiNamedKey(params, consumed, Key.end),
        'H' => parseCsiNamedKey(params, consumed, Key.home),
        'I' => .{ .item = .{ .value = .{ .event = .focus_gained }, .consumed = consumed } },
        'O' => .{ .item = .{ .value = .{ .event = .focus_lost }, .consumed = consumed } },
        'P', 'Q', 'S' => parseCsiNamedKey(params, consumed, Key.unknown(final)),
        'u' => parseCsiUnicode(params, consumed),
        'Z' => keyItem(Key.shift_tab, consumed),
        'M', 'm' => parseCsiMouse(params, final, consumed),
        '~' => parseCsiTilde(params, consumed),
        else => keyItem(Key.unknown(final), consumed),
    };
}

// Handles `CSI <n> ~` style navigation keys and bracketed paste markers.
fn parseCsiTilde(params: []const u8, consumed: usize) DecodeState {
    var fields = std.mem.splitScalar(u8, params, ';');
    const primary_text = fields.next() orelse "";
    const primary = parseUnsigned(primary_text) orelse {
        return keyItem(Key.unknown('~'), consumed);
    };
    const details = parseKeyDetails(fields.next()) orelse return keyItem(Key.unknown('~'), consumed);

    const base = switch (primary) {
        1, 7 => Key.home,
        2 => Key.insert,
        3 => Key.delete,
        4, 8 => Key.end,
        5 => Key.page_up,
        6 => Key.page_down,
        200 => return .{ .item = .{ .value = .paste_start, .consumed = consumed } },
        else => return keyItem(Key.unknown('~'), consumed),
    };

    return keyItem(base.withModifiers(details.modifiers).withEvent(details.event), consumed);
}

// Parses SGR mouse reporting of the form `CSI <Cb;Cx;Cy M` or `m`.
fn parseCsiMouse(params: []const u8, final: u8, consumed: usize) DecodeState {
    if (params.len == 0 or params[0] != '<') {
        return keyItem(Key.unknown(final), consumed);
    }

    var parts = std.mem.splitScalar(u8, params[1..], ';');
    const code_text = parts.next() orelse return keyItem(Key.unknown(final), consumed);
    const x_text = parts.next() orelse return keyItem(Key.unknown(final), consumed);
    const y_text = parts.next() orelse return keyItem(Key.unknown(final), consumed);

    const code = std.fmt.parseInt(u16, code_text, 10) catch return keyItem(Key.unknown(final), consumed);
    const x = std.fmt.parseInt(u16, x_text, 10) catch return keyItem(Key.unknown(final), consumed);
    const y = std.fmt.parseInt(u16, y_text, 10) catch return keyItem(Key.unknown(final), consumed);

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
        'A' => keyItem(Key.up, 3),
        'B' => keyItem(Key.down, 3),
        'C' => keyItem(Key.right, 3),
        'D' => keyItem(Key.left, 3),
        'F' => keyItem(Key.end, 3),
        'H' => keyItem(Key.home, 3),
        else => |value| keyItem(Key.unknown(value), 3),
    };
}

// Parses printable ASCII or a full UTF-8 codepoint.
fn parsePrintable(bytes: []const u8) DecodeState {
    const first = bytes[0];
    if (first >= 0x20 and first < 0x7F) {
        return keyItem(Key.character(first), 1);
    }

    const sequence_len = std.unicode.utf8ByteSequenceLength(first) catch {
        return keyItem(Key.unknown(first), 1);
    };
    if (bytes.len < sequence_len) return .pending;

    const codepoint = std.unicode.utf8Decode(bytes[0..sequence_len]) catch {
        return keyItem(Key.unknown(first), 1);
    };

    return keyItem(Key.character(codepoint), sequence_len);
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

// Handles Kitty-style and xterm-style modified navigation keys where the last
// parameter carries protocol-level modifier metadata.
fn parseCsiNamedKey(params: []const u8, consumed: usize, base: Key) DecodeState {
    const details = parseTrailingKeyDetails(params) orelse return keyItem(base, consumed);
    return keyItem(base.withModifiers(details.modifiers).withEvent(details.event), consumed);
}

// Handles `CSI key-code ; modifiers:event u` sequences from the Kitty
// keyboard protocol.
fn parseCsiUnicode(params: []const u8, consumed: usize) DecodeState {
    var fields = std.mem.splitScalar(u8, params, ';');
    const key_text = fields.next() orelse return keyItem(Key.unknown('u'), consumed);
    const key_code = parseKittyCode(key_text) orelse return keyItem(Key.unknown('u'), consumed);
    const details = parseKeyDetails(fields.next()) orelse return keyItem(Key.unknown('u'), consumed);

    var key = decodeKittyKey(key_code, details.modifiers) orelse return keyItem(Key.unknown(key_code), consumed);
    key = key.withEvent(details.event);
    return keyItem(key, consumed);
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

const KeyDetails = struct {
    modifiers: KeyModifiers = .{},
    event: KeyEventKind = .press,
};

// Pulls protocol-level modifiers from the last CSI parameter when present.
fn parseTrailingKeyDetails(params: []const u8) ?KeyDetails {
    if (params.len == 0) return .{};

    if (std.mem.lastIndexOfScalar(u8, params, ';')) |index| {
        return parseKeyDetails(params[index + 1 ..]);
    }
    return .{};
}

// Parses the `modifier:event` parameter format shared by CSI `u` and modern
// modified functional-key encodings.
fn parseKeyDetails(text: ?[]const u8) ?KeyDetails {
    const value = text orelse return .{};
    if (value.len == 0) return .{};

    var parts = std.mem.splitScalar(u8, value, ':');
    const modifier_value = parseUnsigned(parts.next().?) orelse return null;
    if (modifier_value == 0) return null;

    const event = if (parts.next()) |event_text|
        switch (parseUnsigned(event_text) orelse return null) {
            1 => KeyEventKind.press,
            2 => KeyEventKind.repeat,
            3 => KeyEventKind.release,
            else => return null,
        }
    else
        KeyEventKind.press;

    if (parts.next() != null) return null;

    return .{
        .modifiers = decodeKeyModifiers(modifier_value),
        .event = event,
    };
}

// CSI `u` key numbers can optionally include alternate-key subfields
// separated by `:`, but the base key code always comes first.
fn parseKittyCode(text: []const u8) ?u32 {
    const end = std.mem.indexOfScalar(u8, text, ':') orelse text.len;
    return parseUnsigned(text[0..end]);
}

// Parses a small unsigned decimal field used throughout CSI parameter lists.
fn parseUnsigned(text: []const u8) ?u32 {
    if (text.len == 0) return null;
    return std.fmt.parseUnsigned(u32, text, 10) catch null;
}

// The Kitty protocol stores modifier flags as `1 + bitfield`.
fn decodeKeyModifiers(value: u32) KeyModifiers {
    const actual = if (value == 0) 0 else value - 1;
    return .{
        .shift = (actual & 0b0000_0001) != 0,
        .alt = (actual & 0b0000_0010) != 0,
        .ctrl = (actual & 0b0000_0100) != 0,
        .super = (actual & 0b0000_1000) != 0,
        .hyper = (actual & 0b0001_0000) != 0,
        .meta = (actual & 0b0010_0000) != 0,
        .caps_lock = (actual & 0b0100_0000) != 0,
        .num_lock = (actual & 0b1000_0000) != 0,
    };
}

// Maps Kitty key numbers back into the runtime key surface.
fn decodeKittyKey(code: u32, modifiers: KeyModifiers) ?Key {
    if (modifiers.eql(.{ .ctrl = true })) {
        if (code == 'c' or code == 'C') return Key.ctrl_c;
        if (code == 'z' or code == 'Z') return Key.ctrl_z;
    }

    return switch (code) {
        9 => if (modifiers.eql(.{ .shift = true })) Key.shift_tab else Key.tab,
        13 => Key.enter,
        27 => Key.escape,
        127, 8 => Key.backspace,
        57348 => Key.insert,
        57349 => Key.delete,
        57350 => Key.left,
        57351 => Key.right,
        57352 => Key.up,
        57353 => Key.down,
        57354 => Key.page_up,
        57355 => Key.page_down,
        57356 => Key.home,
        57357 => Key.end,
        else => blk: {
            if (code >= 0x20 and code < 0x110000) {
                break :blk Key.characterWithModifiers(@intCast(code), modifiers);
            }
            break :blk null;
        },
    };
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

test "parses kitty keyboard modified characters and special keys" {
    try std.testing.expectEqualDeep(
        Key.characterWithModifiers('a', .{ .alt = true }),
        parse("\x1b[97;3u").?,
    );
    try std.testing.expectEqualDeep(Key.ctrl_c, parse("\x1b[99;5u").?);
    try std.testing.expectEqualDeep(
        Key.up.withModifiers(.{ .ctrl = true }),
        parse("\x1b[1;5A").?,
    );
}

test "parses kitty keyboard release events when present" {
    try std.testing.expectEqualDeep(
        Key.characterWithModifiers('a', .{ .alt = true }).withEvent(.release),
        parse("\x1b[97;3:3u").?,
    );
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
