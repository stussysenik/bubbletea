const std = @import("std");

/// Runtime knobs for the terminal renderer.
pub const Options = struct {
    alt_screen: bool = true,
    hide_cursor: bool = true,
    ansi_enabled: bool = true,
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

        if (self.started or !self.options.ansi_enabled) {
            self.started = true;
            return;
        }

        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(self.allocator);

        if (self.options.alt_screen) {
            try buffer.appendSlice(self.allocator, "\x1b[?1049h");
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
    pub fn render(self: *Renderer, frame: []const u8) !void {
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
        if (self.previous_cells.eql(&next_cells)) return;

        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(self.allocator);
        try writeCellDiff(&output, self.allocator, &self.previous_cells, &next_cells);

        try self.stdout.writeAll(output.items);
        self.previous_cells.deinit(self.allocator);
        self.previous_cells = next_cells;
        next_cells = .{};
    }
};

// Terminal styling tracked per visible cell instead of per full line.
const CellStyle = enum(u8) {
    normal,
    muted,
    accent,
    success,
    warning,
};

// One visible cell in the flattened terminal grid.
const Cell = struct {
    codepoint: u21 = ' ',
    style: CellStyle = .normal,
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

    fn deinit(self: *CellBuffer, allocator: std.mem.Allocator) void {
        self.rows.deinit(allocator);
        self.cells.deinit(allocator);
    }

    fn clearRetainingCapacity(self: *CellBuffer) void {
        self.rows.clearRetainingCapacity();
        self.cells.clearRetainingCapacity();
    }

    // Parses a rendered frame into styled cells, skipping ANSI SGR sequences
    // while preserving their effect on subsequent glyphs.
    fn parse(self: *CellBuffer, allocator: std.mem.Allocator, frame: []const u8) !void {
        self.clearRetainingCapacity();

        var row_start: usize = 0;
        var row_len: usize = 0;
        var style: CellStyle = .normal;
        var index: usize = 0;

        while (index < frame.len) {
            switch (frame[index]) {
                '\n' => {
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
                    if (consumeAnsi(frame, &index, &style)) continue;
                    index += 1;
                },
                else => {
                    const sequence_len = std.unicode.utf8ByteSequenceLength(frame[index]) catch 1;
                    const end = @min(frame.len, index + sequence_len);
                    const codepoint = std.unicode.utf8Decode(frame[index..end]) catch @as(u21, '?');
                    try self.cells.append(allocator, .{
                        .codepoint = codepoint,
                        .style = style,
                    });
                    row_len += 1;
                    index = end;
                },
            }
        }

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
            if (left.codepoint != right.codepoint or left.style != right.style) return false;
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
            if (cellsEqual(previous.cellAt(row_index, col_index), next.cellAt(row_index, col_index))) {
                col_index += 1;
                continue;
            }

            const run_start = col_index;
            while (col_index < row_width and !cellsEqual(previous.cellAt(row_index, col_index), next.cellAt(row_index, col_index))) {
                col_index += 1;
            }

            try appendCursorMove(output.writer(allocator), row_index + 1, run_start + 1);
            for (run_start..col_index) |run_col| {
                const cell = next.cellAt(row_index, run_col);
                if (cell.style != active_style) {
                    try output.appendSlice(allocator, stylePrefix(cell.style));
                    active_style = cell.style;
                }
                try appendCodepoint(output, allocator, cell.codepoint);
            }
        }
    }

    if (output.items.len != 0 and active_style != .normal) {
        try output.appendSlice(allocator, stylePrefix(.normal));
    }
}

// Exact cell equality used to identify cursor runs that need repainting.
fn cellsEqual(left: Cell, right: Cell) bool {
    return left.codepoint == right.codepoint and left.style == right.style;
}

// Emits a 1-based terminal cursor move.
fn appendCursorMove(writer: anytype, row: usize, col: usize) !void {
    try std.fmt.format(writer, "\x1b[{d};{d}H", .{ row, col });
}

// Emits one UTF-8 codepoint into the diff stream.
fn appendCodepoint(output: *std.ArrayList(u8), allocator: std.mem.Allocator, codepoint: u21) !void {
    var buffer: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(codepoint, &buffer) catch unreachable;
    try output.appendSlice(allocator, buffer[0..len]);
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
    try std.testing.expectEqual(@as(u21, 'a'), buffer.cellAt(0, 0).codepoint);
    try std.testing.expectEqual(CellStyle.normal, buffer.cellAt(0, 0).style);
    try std.testing.expectEqual(@as(u21, 'b'), buffer.cellAt(0, 1).codepoint);
    try std.testing.expectEqual(CellStyle.accent, buffer.cellAt(0, 1).style);
    try std.testing.expectEqual(@as(usize, 0), buffer.rowWidth(1));
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
