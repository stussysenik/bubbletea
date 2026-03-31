const std = @import("std");
const cell_width = @import("cell_width.zig");
const ui = @import("ui.zig");

/// Runtime knobs for the terminal renderer.
pub const Options = struct {
    alt_screen: bool = true,
    hide_cursor: bool = true,
    ansi_enabled: bool = true,
    kitty_keyboard: bool = true,
    bracketed_paste: bool = true,
    focus_reporting: bool = true,
    mouse_mode: MouseMode = .none,
};

/// Terminal mouse tracking mode to enable before the event loop starts.
pub const MouseMode = enum {
    none,
    click,
    drag,
    motion,
};

/// Cell-buffer renderer that rewrites only the changed terminal glyph runs.
pub const Renderer = struct {
    allocator: std.mem.Allocator,
    stdout: std.fs.File,
    previous_frame: std.ArrayList(u8) = .empty,
    previous_cells: CellBuffer = .{},
    last_cursor: ?Cursor = null,
    cursor_visible: bool = false,
    started: bool = false,
    options: Options,

    pub fn init(allocator: std.mem.Allocator, stdout: std.fs.File, options: Options) Renderer {
        return .{
            .allocator = allocator,
            .stdout = stdout,
            .options = options,
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.previous_frame.deinit(self.allocator);
        self.previous_cells.deinit(self.allocator);
    }

    /// Enables terminal modes needed for full-screen rendering.
    pub fn start(self: *Renderer) !void {
        self.previous_frame.clearRetainingCapacity();
        self.previous_cells.clearRetainingCapacity();
        self.last_cursor = null;
        self.cursor_visible = !self.options.hide_cursor;

        if (self.started or !self.options.ansi_enabled) {
            self.started = true;
            return;
        }

        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(self.allocator);

        if (self.options.alt_screen) {
            try buffer.appendSlice(self.allocator, "\x1b[?1049h");
        }
        // Kitty's keyboard mode stack restores cleanly with CSI < u on exit,
        // which makes it safe to opt into simpler unambiguous key encoding.
        if (self.options.kitty_keyboard) {
            try buffer.appendSlice(self.allocator, "\x1b[>1u");
        }
        if (self.options.hide_cursor) {
            try buffer.appendSlice(self.allocator, "\x1b[?25l");
        }
        if (self.options.bracketed_paste) {
            try buffer.appendSlice(self.allocator, "\x1b[?2004h");
        }
        if (self.options.focus_reporting) {
            try buffer.appendSlice(self.allocator, "\x1b[?1004h");
        }
        switch (self.options.mouse_mode) {
            .none => {},
            .click => try buffer.appendSlice(self.allocator, "\x1b[?1000h\x1b[?1006h"),
            .drag => try buffer.appendSlice(self.allocator, "\x1b[?1002h\x1b[?1006h"),
            .motion => try buffer.appendSlice(self.allocator, "\x1b[?1003h\x1b[?1006h"),
        }
        try buffer.appendSlice(self.allocator, "\x1b[0m\x1b[2J\x1b[H");

        try self.stdout.writeAll(buffer.items);
        self.started = true;
    }

    /// Restores cursor visibility and screen state when the program exits.
    pub fn stop(self: *Renderer) !void {
        if (!self.started or !self.options.ansi_enabled) {
            self.started = false;
            return;
        }

        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(self.allocator);

        try buffer.appendSlice(self.allocator, "\x1b[0m");
        switch (self.options.mouse_mode) {
            .none => {},
            .click => try buffer.appendSlice(self.allocator, "\x1b[?1000l\x1b[?1006l"),
            .drag => try buffer.appendSlice(self.allocator, "\x1b[?1002l\x1b[?1006l"),
            .motion => try buffer.appendSlice(self.allocator, "\x1b[?1003l\x1b[?1006l"),
        }
        if (self.options.kitty_keyboard) {
            try buffer.appendSlice(self.allocator, "\x1b[<u");
        }
        if (self.options.focus_reporting) {
            try buffer.appendSlice(self.allocator, "\x1b[?1004l");
        }
        if (self.options.bracketed_paste) {
            try buffer.appendSlice(self.allocator, "\x1b[?2004l");
        }
        if (self.options.hide_cursor) {
            try buffer.appendSlice(self.allocator, "\x1b[?25h");
        }
        if (self.options.alt_screen) {
            try buffer.appendSlice(self.allocator, "\x1b[?1049l");
        } else {
            try buffer.append(self.allocator, '\n');
        }

        try self.stdout.writeAll(buffer.items);
        self.started = false;
    }

    /// Writes either the whole frame or a row-level diff depending on host
    /// capabilities.
    pub fn render(self: *Renderer, frame: []const u8, cursor: ?Cursor) !void {
        if (!self.options.ansi_enabled) {
            if (std.mem.eql(u8, self.previous_frame.items, frame)) return;

            // Headless and piped output stay plain so tests and non-TTY hosts
            // can snapshot the frame directly.
            try self.stdout.writeAll(frame);
            self.previous_frame.clearRetainingCapacity();
            try self.previous_frame.appendSlice(self.allocator, frame);
            return;
        }

        // ANSI rendering diffs the terminal as styled cells instead of whole
        // lines so short edits only rewrite the changed glyph runs.
        var next_cells = CellBuffer{};
        defer next_cells.deinit(self.allocator);
        try next_cells.parse(self.allocator, frame);
        const cells_changed = !self.previous_cells.eql(&next_cells);
        const cursor_changed = !cursorEqual(self.last_cursor, cursor);
        if (!cells_changed and !cursor_changed) return;

        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(self.allocator);
        if (cells_changed) {
            try writeCellDiff(&output, self.allocator, &self.previous_cells, &next_cells);
        }
        try writeCursorState(&output, self.allocator, cursor, &self.cursor_visible);

        try self.stdout.writeAll(output.items);
        if (cells_changed) {
            self.previous_cells.deinit(self.allocator);
            self.previous_cells = next_cells;
            next_cells = .{};
        }
        self.last_cursor = cursor;
    }
};

/// Terminal cursor position reported by the shared UI renderer.
pub const Cursor = ui.Cursor;

// Terminal styling tracked per visible cell instead of per full line.
const CellStyle = enum(u8) {
    normal,
    muted,
    accent,
    success,
    warning,
};

const CellKind = enum(u8) {
    glyph,
    continuation,
};

const GlyphRange = struct {
    start: usize = 0,
    len: usize = 0,
};

// One visible terminal cell in the flattened grid.
const Cell = struct {
    kind: CellKind = .glyph,
    glyph: GlyphRange = .{},
    style: CellStyle = .normal,
    blank: bool = true,
};

// Row slice inside the flat cell storage.
const RowRange = struct {
    start: usize,
    len: usize,
};

// Parsed terminal frame used for precise cell-by-cell diffing.
const CellBuffer = struct {
    rows: std.ArrayList(RowRange) = .empty,
    cells: std.ArrayList(Cell) = .empty,
    glyph_bytes: std.ArrayList(u8) = .empty,

    fn deinit(self: *CellBuffer, allocator: std.mem.Allocator) void {
        self.rows.deinit(allocator);
        self.cells.deinit(allocator);
        self.glyph_bytes.deinit(allocator);
    }

    fn clearRetainingCapacity(self: *CellBuffer) void {
        self.rows.clearRetainingCapacity();
        self.cells.clearRetainingCapacity();
        self.glyph_bytes.clearRetainingCapacity();
    }

    // Parses a rendered frame into styled cells, skipping ANSI SGR sequences
    // while preserving their effect on subsequent glyphs.
    fn parse(self: *CellBuffer, allocator: std.mem.Allocator, frame: []const u8) !void {
        self.clearRetainingCapacity();

        var row_start: usize = 0;
        var row_len: usize = 0;
        var style: CellStyle = .normal;
        var index: usize = 0;
        var pending: PendingCluster = .{};

        while (index < frame.len) {
            switch (frame[index]) {
                '\n' => {
                    try self.flushPendingCluster(allocator, &pending, &row_len);
                    try self.rows.append(allocator, .{
                        .start = row_start,
                        .len = row_len,
                    });
                    row_start = self.cells.items.len;
                    row_len = 0;
                    index += 1;
                },
                '\r' => index += 1,
                0x1b => {
                    try self.flushPendingCluster(allocator, &pending, &row_len);
                    if (consumeAnsi(frame, &index, &style)) continue;
                    index += 1;
                },
                else => {
                    const sequence_len = std.unicode.utf8ByteSequenceLength(frame[index]) catch 1;
                    const end = @min(frame.len, index + sequence_len);
                    const bytes = frame[index..end];
                    const codepoint = std.unicode.utf8Decode(bytes) catch @as(u21, '?');
                    const width = cell_width.scalarWidth(codepoint);
                    const extends_cluster = pending.active and (width == 0 or pending.join_pending);

                    if (extends_cluster) {
                        if (!pending.blank or codepoint != ' ') {
                            if (pending.blank and codepoint != ' ') {
                                pending.blank = false;
                                pending.start = self.glyph_bytes.items.len;
                            }
                            if (codepoint != ' ') {
                                try self.glyph_bytes.appendSlice(allocator, bytes);
                                pending.len += bytes.len;
                            }
                        }
                        pending.width = @max(pending.width, width);
                        pending.join_pending = codepoint == 0x200D;
                        index = end;
                        continue;
                    }

                    try self.flushPendingCluster(allocator, &pending, &row_len);
                    if (width == 0) {
                        index = end;
                        continue;
                    }

                    pending = .{
                        .active = true,
                        .style = style,
                        .width = width,
                        .blank = codepoint == ' ',
                        .join_pending = codepoint == 0x200D,
                    };
                    if (codepoint != ' ') {
                        pending.start = self.glyph_bytes.items.len;
                        try self.glyph_bytes.appendSlice(allocator, bytes);
                        pending.len = bytes.len;
                    }
                    index = end;
                },
            }
        }

        try self.flushPendingCluster(allocator, &pending, &row_len);
        try self.rows.append(allocator, .{
            .start = row_start,
            .len = row_len,
        });
    }

    fn eql(self: *const CellBuffer, other: *const CellBuffer) bool {
        if (self.rows.items.len != other.rows.items.len) return false;
        if (self.cells.items.len != other.cells.items.len) return false;

        for (self.rows.items, other.rows.items) |left, right| {
            if (left.len != right.len) return false;
        }

        for (self.cells.items, other.cells.items) |left, right| {
            if (!cellsEqual(self, left, other, right)) return false;
        }

        return true;
    }

    fn rowWidth(self: *const CellBuffer, row_index: usize) usize {
        if (row_index >= self.rows.items.len) return 0;
        return self.rows.items[row_index].len;
    }

    fn cellAt(self: *const CellBuffer, row_index: usize, col_index: usize) Cell {
        if (row_index >= self.rows.items.len) return .{};

        const row = self.rows.items[row_index];
        if (col_index >= row.len) return .{};
        return self.cells.items[row.start + col_index];
    }

    fn glyphSlice(self: *const CellBuffer, cell: Cell) []const u8 {
        return self.glyph_bytes.items[cell.glyph.start..][0..cell.glyph.len];
    }

    fn flushPendingCluster(
        self: *CellBuffer,
        allocator: std.mem.Allocator,
        pending: *PendingCluster,
        row_len: *usize,
    ) !void {
        if (!pending.active) return;

        try self.cells.append(allocator, .{
            .kind = .glyph,
            .glyph = .{
                .start = pending.start,
                .len = pending.len,
            },
            .style = pending.style,
            .blank = pending.blank,
        });
        if (pending.width == 2) {
            try self.cells.append(allocator, .{
                .kind = .continuation,
                .style = pending.style,
                .blank = false,
            });
        }

        row_len.* += pending.width;
        pending.* = .{};
    }
};

const PendingCluster = struct {
    active: bool = false,
    start: usize = 0,
    len: usize = 0,
    width: usize = 0,
    style: CellStyle = .normal,
    blank: bool = true,
    join_pending: bool = false,
};

// Parses one ANSI CSI sequence and updates the current cell style when the
// sequence is an SGR code.
fn consumeAnsi(frame: []const u8, index: *usize, style: *CellStyle) bool {
    if (index.* + 1 >= frame.len or frame[index.* + 1] != '[') return false;

    var cursor = index.* + 2;
    while (cursor < frame.len) : (cursor += 1) {
        const byte = frame[cursor];
        if (byte < 0x40 or byte > 0x7e) continue;

        if (byte == 'm') {
            style.* = parseStyle(frame[index.* + 2 .. cursor], style.*);
        }
        index.* = cursor + 1;
        return true;
    }

    return false;
}

// Maps the renderer's known SGR sequences back to semantic cell styles.
fn parseStyle(params: []const u8, current: CellStyle) CellStyle {
    if (params.len == 0) return .normal;

    var style = current;
    var parts = std.mem.splitScalar(u8, params, ';');
    while (parts.next()) |part| {
        if (part.len == 0) {
            style = .normal;
            continue;
        }

        const value = std.fmt.parseUnsigned(u8, part, 10) catch continue;
        style = switch (value) {
            0, 39 => .normal,
            90 => .muted,
            92 => .success,
            93 => .warning,
            96 => .accent,
            else => style,
        };
    }

    return style;
}

// Writes a cursor-positioned diff between two parsed cell buffers.
fn writeCellDiff(
    output: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    previous: *const CellBuffer,
    next: *const CellBuffer,
) !void {
    const max_rows = @max(previous.rows.items.len, next.rows.items.len);
    var active_style: CellStyle = .normal;

    for (0..max_rows) |row_index| {
        const row_width = @max(previous.rowWidth(row_index), next.rowWidth(row_index));
        var col_index: usize = 0;

        while (col_index < row_width) {
            if (cellsEqual(previous, previous.cellAt(row_index, col_index), next, next.cellAt(row_index, col_index))) {
                col_index += 1;
                continue;
            }

            const run_start = col_index;
            while (col_index < row_width and !cellsEqual(previous, previous.cellAt(row_index, col_index), next, next.cellAt(row_index, col_index))) {
                col_index += 1;
            }

            try appendCursorMove(output.writer(allocator), row_index + 1, run_start + 1);
            for (run_start..col_index) |run_col| {
                const cell = next.cellAt(row_index, run_col);
                if (cell.kind == .continuation) continue;
                if (cell.style != active_style) {
                    try output.appendSlice(allocator, stylePrefix(cell.style));
                    active_style = cell.style;
                }
                try appendCellGlyph(output, allocator, next, cell);
            }
        }
    }

    if (output.items.len != 0 and active_style != .normal) {
        try output.appendSlice(allocator, stylePrefix(.normal));
    }
}

// Exact cell equality used to identify cursor runs that need repainting.
fn cellsEqual(left_buffer: *const CellBuffer, left: Cell, right_buffer: *const CellBuffer, right: Cell) bool {
    if (left.kind != right.kind or left.style != right.style or left.blank != right.blank) return false;
    if (left.kind == .continuation or left.blank) return true;
    return std.mem.eql(u8, left_buffer.glyphSlice(left), right_buffer.glyphSlice(right));
}

fn cursorEqual(left: ?Cursor, right: ?Cursor) bool {
    if (left == null and right == null) return true;
    if (left == null or right == null) return false;
    return left.?.x == right.?.x and left.?.y == right.?.y;
}

// Emits a 1-based terminal cursor move.
fn appendCursorMove(writer: anytype, row: usize, col: usize) !void {
    try std.fmt.format(writer, "\x1b[{d};{d}H", .{ row, col });
}

// Applies cursor visibility and movement after any cell updates.
fn writeCursorState(
    output: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    cursor: ?Cursor,
    cursor_visible: *bool,
) !void {
    if (cursor) |value| {
        if (!cursor_visible.*) {
            try output.appendSlice(allocator, "\x1b[?25h");
            cursor_visible.* = true;
        }
        try appendCursorMove(output.writer(allocator), value.y + 1, value.x + 1);
        return;
    }

    if (cursor_visible.*) {
        try output.appendSlice(allocator, "\x1b[?25l");
        cursor_visible.* = false;
    }
}

// Emits the visible glyph for one cell into the diff stream.
fn appendCellGlyph(output: *std.ArrayList(u8), allocator: std.mem.Allocator, buffer: *const CellBuffer, cell: Cell) !void {
    if (cell.blank) {
        try output.append(allocator, ' ');
        return;
    }
    try output.appendSlice(allocator, buffer.glyphSlice(cell));
}

// ANSI prefix used for the given semantic style.
fn stylePrefix(style: CellStyle) []const u8 {
    return switch (style) {
        .normal => "\x1b[0m",
        .muted => "\x1b[90m",
        .accent => "\x1b[1;96m",
        .success => "\x1b[1;92m",
        .warning => "\x1b[1;93m",
    };
}

test "cell buffer parses styled frames" {
    var buffer = CellBuffer{};
    defer buffer.deinit(std.testing.allocator);

    try buffer.parse(std.testing.allocator, "a\x1b[1;96mb\x1b[0m\n");
    try std.testing.expectEqual(@as(usize, 2), buffer.rows.items.len);
    try std.testing.expectEqual(@as(usize, 2), buffer.rowWidth(0));
    try std.testing.expectEqualStrings("a", buffer.glyphSlice(buffer.cellAt(0, 0)));
    try std.testing.expectEqual(CellStyle.normal, buffer.cellAt(0, 0).style);
    try std.testing.expectEqualStrings("b", buffer.glyphSlice(buffer.cellAt(0, 1)));
    try std.testing.expectEqual(CellStyle.accent, buffer.cellAt(0, 1).style);
    try std.testing.expectEqual(@as(usize, 0), buffer.rowWidth(1));
}

test "cell buffer tracks wide and combining glyphs by terminal width" {
    var buffer = CellBuffer{};
    defer buffer.deinit(std.testing.allocator);

    try buffer.parse(std.testing.allocator, "e\u{0301}漢");
    try std.testing.expectEqual(@as(usize, 3), buffer.rowWidth(0));
    try std.testing.expectEqualStrings("e\u{0301}", buffer.glyphSlice(buffer.cellAt(0, 0)));
    try std.testing.expectEqualStrings("漢", buffer.glyphSlice(buffer.cellAt(0, 1)));
    try std.testing.expectEqual(CellKind.continuation, buffer.cellAt(0, 2).kind);
}

test "cell diff rewrites only changed glyphs" {
    var previous = CellBuffer{};
    defer previous.deinit(std.testing.allocator);
    try previous.parse(std.testing.allocator, "alpha\nbeta");

    var next = CellBuffer{};
    defer next.deinit(std.testing.allocator);
    try next.parse(std.testing.allocator, "alpha\nbeXa");

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);

    try writeCellDiff(&output, std.testing.allocator, &previous, &next);
    try std.testing.expectEqualStrings("\x1b[2;3HX", output.items);
}

test "cell diff clears trailing cells when rows shrink" {
    var previous = CellBuffer{};
    defer previous.deinit(std.testing.allocator);
    try previous.parse(std.testing.allocator, "abcd");

    var next = CellBuffer{};
    defer next.deinit(std.testing.allocator);
    try next.parse(std.testing.allocator, "ab");

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);

    try writeCellDiff(&output, std.testing.allocator, &previous, &next);
    try std.testing.expectEqualStrings("\x1b[1;3H  ", output.items);
}

test "cell diff preserves semantic ANSI styles" {
    var previous = CellBuffer{};
    defer previous.deinit(std.testing.allocator);
    try previous.parse(std.testing.allocator, "");

    var next = CellBuffer{};
    defer next.deinit(std.testing.allocator);
    try next.parse(std.testing.allocator, "\x1b[1;96mA\x1b[0m");

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);

    try writeCellDiff(&output, std.testing.allocator, &previous, &next);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\x1b[1;96mA\x1b[0m") != null);
}

test "cell diff preserves wide glyph clusters" {
    var previous = CellBuffer{};
    defer previous.deinit(std.testing.allocator);
    try previous.parse(std.testing.allocator, "ab");

    var next = CellBuffer{};
    defer next.deinit(std.testing.allocator);
    try next.parse(std.testing.allocator, "a漢");

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);

    try writeCellDiff(&output, std.testing.allocator, &previous, &next);
    try std.testing.expectEqualStrings("\x1b[1;2H漢", output.items);
}

test "cursor state shows and positions the real terminal cursor" {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);

    var visible = false;
    try writeCursorState(&output, std.testing.allocator, .{ .x = 4, .y = 1 }, &visible);
    try std.testing.expect(visible);
    try std.testing.expectEqualStrings("\x1b[?25h\x1b[2;5H", output.items);
}

test "cursor state hides the terminal cursor when absent" {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);

    var visible = true;
    try writeCursorState(&output, std.testing.allocator, null, &visible);
    try std.testing.expect(!visible);
    try std.testing.expectEqualStrings("\x1b[?25l", output.items);
}
