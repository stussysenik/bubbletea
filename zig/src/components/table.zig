const std = @import("std");
const ui = @import("../ui.zig");

/// Lightweight read-only table for dashboards, inspectors, and admin views.
pub const Table = struct {
    headers: []const []const u8,
    rows: []const []const []const u8,
    empty_label: []const u8 = "(no rows)",
    header_tone: ui.Tone = .accent,
    separator_tone: ui.Tone = .muted,
    selected_row: ?usize = null,
    selected_tone: ui.Tone = .success,

    /// Formats headers and rows into aligned text lines inside the tree.
    pub fn compose(self: *const Table, tree: *ui.Tree) !ui.NodeId {
        const allocator = tree.allocator();
        const column_count = self.columnCount();
        if (column_count == 0) {
            return tree.textStyled(self.empty_label, .{ .tone = .muted });
        }

        const widths = try allocator.alloc(usize, column_count);
        @memset(widths, 0);
        self.computeWidths(widths);

        const has_header = self.headers.len != 0;
        const body_rows = if (self.rows.len == 0) 1 else self.rows.len;
        const header_nodes: usize = if (has_header) 2 else 0;
        const total_nodes = body_rows + header_nodes;
        const nodes = try tree.allocNodeIds(total_nodes);
        var count: usize = 0;

        if (has_header) {
            const header_line = try formatRow(allocator, self.headers, widths);
            nodes[count] = try tree.textStyled(header_line, .{ .tone = self.header_tone });
            count += 1;

            const separator = try formatSeparator(allocator, widths);
            nodes[count] = try tree.textStyled(separator, .{ .tone = self.separator_tone });
            count += 1;
        }

        if (self.rows.len == 0) {
            nodes[count] = try tree.textStyled(self.empty_label, .{ .tone = .muted });
            count += 1;
        } else {
            for (self.rows, 0..) |row, row_index| {
                const line = try formatRow(allocator, row, widths);
                if (self.selected_row != null and self.selected_row.? == row_index) {
                    nodes[count] = try tree.textStyled(line, .{ .tone = self.selected_tone });
                } else {
                    nodes[count] = try tree.text(line);
                }
                count += 1;
            }
        }

        return tree.column(nodes[0..count], .{ .gap = 0 });
    }

    /// Uses the widest header or cell count as the table width.
    fn columnCount(self: *const Table) usize {
        var count = self.headers.len;
        for (self.rows) |row| {
            count = @max(count, row.len);
        }
        return count;
    }

    /// Computes display widths so ASCII separators line up cleanly.
    fn computeWidths(self: *const Table, widths: []usize) void {
        for (self.headers, 0..) |cell, index| {
            widths[index] = @max(widths[index], displayWidth(cell));
        }

        for (self.rows) |row| {
            for (row, 0..) |cell, index| {
                widths[index] = @max(widths[index], displayWidth(cell));
            }
        }
    }
};

// Formats one logical row with padded cells.
fn formatRow(allocator: std.mem.Allocator, cells: []const []const u8, widths: []const usize) ![]u8 {
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    for (widths, 0..) |width, index| {
        const cell = if (index < cells.len) cells[index] else "";
        try buffer.appendSlice(allocator, cell);
        try appendRepeated(allocator, &buffer, ' ', width - displayWidth(cell));
        if (index + 1 < widths.len) {
            try buffer.appendSlice(allocator, " | ");
        }
    }

    return allocator.dupe(u8, buffer.items);
}

// Builds the `---+---` style separator row under the header.
fn formatSeparator(allocator: std.mem.Allocator, widths: []const usize) ![]u8 {
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    for (widths, 0..) |width, index| {
        try appendRepeated(allocator, &buffer, '-', width);
        if (index + 1 < widths.len) {
            try buffer.appendSlice(allocator, "-+-");
        }
    }

    return allocator.dupe(u8, buffer.items);
}

// Appends repeated padding bytes into a temporary line buffer.
fn appendRepeated(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), byte: u8, count: usize) !void {
    if (count == 0) return;
    const slice = try buffer.addManyAsSlice(allocator, count);
    @memset(slice, byte);
}

// Width is tracked in codepoints for now; cell-buffer rendering can tighten
// this later.
fn displayWidth(text: []const u8) usize {
    return std.unicode.utf8CountCodepoints(text) catch text.len;
}

test "table renders headers and selected row" {
    const headers = [_][]const u8{ "Status", "Area", "Notes" };
    const row_a = [_][]const u8{ "Done", "Runtime", "headless core" };
    const row_b = [_][]const u8{ "Next", "Input", "mouse + paste" };
    const rows = [_][]const []const u8{ &row_a, &row_b };

    var tree = ui.Tree.init(std.testing.allocator);
    defer tree.deinit();

    const table = Table{
        .headers = &headers,
        .rows = &rows,
        .selected_row = 1,
    };

    const root = try table.compose(&tree);
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    try tree.render(buffer.writer(std.testing.allocator), root, .{ .ansi = false });
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "Status | Area") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "Input") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "---") != null);
}
