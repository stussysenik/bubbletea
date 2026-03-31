const std = @import("std");
const cell_width = @import("cell_width.zig");

/// Stable handle for nodes stored in the per-frame tree arena.
pub const NodeId = u32;

/// Stack direction for rows and columns.
pub const Axis = enum {
    horizontal,
    vertical,
};

/// Border style supported by boxed nodes.
pub const Border = enum {
    none,
    single,
};

/// Semantic styling tone understood by terminal and future browser hosts.
pub const Tone = enum {
    normal,
    muted,
    accent,
    success,
    warning,
};

/// Horizontal alignment inside fixed-width regions.
pub const Align = enum {
    left,
    center,
    right,
};

/// Edge padding for boxed content.
pub const Insets = struct {
    top: usize = 0,
    right: usize = 0,
    bottom: usize = 0,
    left: usize = 0,

    /// Applies the same padding to all four edges.
    pub fn all(value: usize) Insets {
        return .{
            .top = value,
            .right = value,
            .bottom = value,
            .left = value,
        };
    }

    /// Applies separate vertical and horizontal padding values.
    pub fn symmetric(vertical: usize, horizontal: usize) Insets {
        return .{
            .top = vertical,
            .right = horizontal,
            .bottom = vertical,
            .left = horizontal,
        };
    }
};

/// Styling options for text nodes.
pub const TextOptions = struct {
    alignment: Align = .left,
    tone: Tone = .normal,
};

/// Shared stack options for rows and columns.
pub const StackOptions = struct {
    gap: usize = 0,
};

/// Styling and layout options for boxed nodes.
pub const BoxOptions = struct {
    title: ?[]const u8 = null,
    region: ?[]const u8 = null,
    action: ?Action = null,
    padding: Insets = .{},
    border: Border = .single,
    alignment: Align = .left,
    tone: Tone = .normal,
};

/// Options for horizontal rule nodes.
pub const RuleOptions = struct {
    tone: Tone = .muted,
    glyph: u21 = '-',
};

/// Host-facing rendering flags.
pub const RenderOptions = struct {
    ansi: bool = true,
};

/// Shared display-width helper used by layout-sensitive components.
pub const displayWidth = cell_width.displayWidth;

/// Terminal-space cursor position derived from the composed view tree.
pub const Cursor = struct {
    x: usize,
    y: usize,
};

const ChildRange = struct {
    start: usize,
    len: usize,
};

const TextNode = struct {
    content: []const u8,
    alignment: Align,
    tone: Tone,
};

const CursorNode = struct {
    tone: Tone,
};

const StackNode = struct {
    axis: Axis,
    children: ChildRange,
    gap: usize,
};

/// Browser-facing action metadata attached to interactive UI regions.
pub const Action = struct {
    kind: []const u8,
    value: usize,
};

const BoxNode = struct {
    child: NodeId,
    title: ?[]const u8,
    region: ?[]const u8,
    action: ?Action,
    padding: Insets,
    border: Border,
    alignment: Align,
    tone: Tone,
};

const SpacerNode = struct {
    width: usize,
    height: usize,
};

const RuleNode = struct {
    width: usize,
    glyph: u21,
    tone: Tone,
};

const Node = union(enum) {
    text: TextNode,
    cursor: CursorNode,
    stack: StackNode,
    box: BoxNode,
    spacer: SpacerNode,
    rule: RuleNode,
};

// Measured size in terminal cell units. Browser hosts can translate the same
// values into pixels after measuring one monospace cell locally.
const LayoutSize = struct {
    width: usize,
    height: usize,
};

// Top-left origin for one node in the composed grid.
const LayoutOrigin = struct {
    x: usize = 0,
    y: usize = 0,
};

// Full frame data attached to every serialized node.
const LayoutFrame = struct {
    x: usize,
    y: usize,
    width: usize,
    height: usize,
};

/// Arena-backed scene graph used to compose one frame at a time.
pub const Tree = struct {
    arena_state: std.heap.ArenaAllocator,
    nodes: std.ArrayList(Node) = .empty,
    children: std.ArrayList(NodeId) = .empty,

    /// Creates a tree whose allocations all die together after a frame render.
    pub fn init(parent_allocator: std.mem.Allocator) Tree {
        return .{
            .arena_state = std.heap.ArenaAllocator.init(parent_allocator),
        };
    }

    /// Releases the arena and any node storage built during composition.
    pub fn deinit(self: *Tree) void {
        const arena = self.allocator();
        self.children.deinit(arena);
        self.nodes.deinit(arena);
        self.arena_state.deinit();
    }

    /// Returns the allocator backing this frame tree.
    pub fn allocator(self: *Tree) std.mem.Allocator {
        return self.arena_state.allocator();
    }

    /// Allocates a temporary node-id slice for bulk child construction.
    pub fn allocNodeIds(self: *Tree, count: usize) ![]NodeId {
        return self.allocator().alloc(NodeId, count);
    }

    /// Creates an unstyled text node.
    pub fn text(self: *Tree, content: []const u8) !NodeId {
        return self.textStyled(content, .{});
    }

    /// Creates a styled text node.
    pub fn textStyled(self: *Tree, content: []const u8, options: TextOptions) !NodeId {
        return self.appendNode(.{
            .text = .{
                .content = content,
                .alignment = options.alignment,
                .tone = options.tone,
            },
        });
    }

    /// Creates a semantic cursor node instead of embedding a literal glyph.
    pub fn cursor(self: *Tree, tone: Tone) !NodeId {
        return self.appendNode(.{
            .cursor = .{
                .tone = tone,
            },
        });
    }

    /// Formats text directly into the frame arena.
    pub fn format(self: *Tree, comptime fmt: []const u8, args: anytype) !NodeId {
        const content = try std.fmt.allocPrint(self.allocator(), fmt, args);
        return self.text(content);
    }

    /// Creates a horizontal stack.
    pub fn row(self: *Tree, children: []const NodeId, options: StackOptions) !NodeId {
        return self.stack(.horizontal, children, options);
    }

    /// Creates a vertical stack.
    pub fn column(self: *Tree, children: []const NodeId, options: StackOptions) !NodeId {
        return self.stack(.vertical, children, options);
    }

    /// Creates a stack node shared by rows and columns.
    pub fn stack(self: *Tree, axis: Axis, children: []const NodeId, options: StackOptions) !NodeId {
        return self.appendNode(.{
            .stack = .{
                .axis = axis,
                .children = try self.appendChildren(children),
                .gap = options.gap,
            },
        });
    }

    /// Wraps a child in padding, borders, and an optional title.
    pub fn box(self: *Tree, child: NodeId, options: BoxOptions) !NodeId {
        return self.appendNode(.{
            .box = .{
                .child = child,
                .title = options.title,
                .region = options.region,
                .action = options.action,
                .padding = options.padding,
                .border = options.border,
                .alignment = options.alignment,
                .tone = options.tone,
            },
        });
    }

    /// Creates a fixed-size blank region.
    pub fn spacer(self: *Tree, width: usize, height: usize) !NodeId {
        return self.appendNode(.{
            .spacer = .{
                .width = width,
                .height = height,
            },
        });
    }

    /// Creates a divider line rendered with a repeated glyph.
    pub fn rule(self: *Tree, width: usize, options: RuleOptions) !NodeId {
        return self.appendNode(.{
            .rule = .{
                .width = width,
                .glyph = options.glyph,
                .tone = options.tone,
            },
        });
    }

    /// Renders the tree root into any writer.
    pub fn render(self: *Tree, writer: anytype, root: NodeId, options: RenderOptions) !void {
        _ = try self.renderWithCursor(writer, root, options);
    }

    /// Renders the tree root and reports any semantic cursor position.
    pub fn renderWithCursor(self: *Tree, writer: anytype, root: NodeId, options: RenderOptions) !?Cursor {
        var block = try renderNode(self, root, .{ .ansi = options.ansi });
        defer block.deinit();
        try block.writeTo(writer);
        return block.cursor;
    }

    /// Serializes one frame tree into a JSON structure suitable for browser
    /// hosts that want to render real DOM nodes instead of flattened text.
    pub fn writeJson(self: *Tree, writer: anytype, root: NodeId) !void {
        try writeNodeJson(self, writer, root);
    }

    fn appendChildren(self: *Tree, values: []const NodeId) !ChildRange {
        const start = self.children.items.len;
        try self.children.appendSlice(self.allocator(), values);
        return .{
            .start = start,
            .len = values.len,
        };
    }

    fn appendNode(self: *Tree, node: Node) !NodeId {
        const id: NodeId = @intCast(self.nodes.items.len);
        try self.nodes.append(self.allocator(), node);
        return id;
    }

    fn childrenFor(self: *const Tree, range: ChildRange) []const NodeId {
        return self.children.items[range.start..][0..range.len];
    }
};

/// Renders a model through `compose` when present, or falls back to `view`.
pub fn renderModel(
    comptime ModelType: type,
    allocator: std.mem.Allocator,
    model: *const ModelType,
    frame_buffer: *std.ArrayList(u8),
    options: RenderOptions,
) !void {
    _ = try renderModelWithCursor(ModelType, allocator, model, frame_buffer, options);
}

/// Renders a model and returns any semantic cursor position from the composed
/// tree.
pub fn renderModelWithCursor(
    comptime ModelType: type,
    allocator: std.mem.Allocator,
    model: *const ModelType,
    frame_buffer: *std.ArrayList(u8),
    options: RenderOptions,
) !?Cursor {
    frame_buffer.clearRetainingCapacity();

    if (@hasDecl(ModelType, "compose")) {
        var tree = Tree.init(allocator);
        defer tree.deinit();

        const root = try model.compose(&tree);
        const writer = frame_buffer.writer(allocator);
        return try tree.renderWithCursor(writer, root, options);
    }

    if (@hasDecl(ModelType, "view")) {
        const writer = frame_buffer.writer(allocator);
        try model.view(writer);
        return null;
    }

    @compileError("ModelType must declare either compose(self: *const ModelType, tree: *ui.Tree) !ui.NodeId or view(self: *const ModelType, writer: anytype) !void");
}

/// Serializes a model into a structured JSON snapshot.
///
/// Compose-capable models emit their full scene graph, while legacy
/// `view`-only models fall back to one plain text node so browser hosts still
/// have something consistent to render.
pub fn renderModelJson(
    comptime ModelType: type,
    allocator: std.mem.Allocator,
    model: *const ModelType,
    writer: anytype,
) !void {
    if (@hasDecl(ModelType, "compose")) {
        var tree = Tree.init(allocator);
        defer tree.deinit();

        const root = try model.compose(&tree);
        try tree.writeJson(writer, root);
        return;
    }

    if (@hasDecl(ModelType, "view")) {
        var frame_buffer: std.ArrayList(u8) = .empty;
        defer frame_buffer.deinit(allocator);

        try model.view(frame_buffer.writer(allocator));
        const size = measureTextContent(frame_buffer.items);
        try writer.writeAll("{\"kind\":\"text\",\"content\":");
        try writeJsonString(writer, frame_buffer.items);
        try writer.writeAll(",\"layout\":");
        try writeLayoutJson(writer, .{
            .x = 0,
            .y = 0,
            .width = size.width,
            .height = size.height,
        });
        try writer.writeAll(",\"tone\":\"normal\",\"alignment\":\"left\"}");
        return;
    }

    @compileError("ModelType must declare either compose(self: *const ModelType, tree: *ui.Tree) !ui.NodeId or view(self: *const ModelType, writer: anytype) !void");
}

// Emits one node and any recursive children as a browser-consumable JSON
// object. This keeps the browser bridge thin while still reusing the real Zig
// composition tree.
fn writeNodeJson(tree: *const Tree, writer: anytype, node_id: NodeId) !void {
    try writeNodeJsonAt(tree, writer, node_id, .{});
}

// Walks the scene graph in layout order so every serialized node carries its
// measured bounds inside the root grid.
fn writeNodeJsonAt(tree: *const Tree, writer: anytype, node_id: NodeId, origin: LayoutOrigin) !void {
    const size = measureNode(tree, node_id);

    switch (tree.nodes.items[node_id]) {
        .text => |text_node| {
            try writer.writeAll("{\"kind\":\"text\",\"content\":");
            try writeJsonString(writer, text_node.content);
            try writer.writeAll(",\"layout\":");
            try writeLayoutJson(writer, makeFrame(origin, size));
            try writer.writeAll(",\"tone\":");
            try writeJsonEnumTag(writer, text_node.tone);
            try writer.writeAll(",\"alignment\":");
            try writeJsonEnumTag(writer, text_node.alignment);
            try writer.writeByte('}');
        },
        .cursor => |cursor_node| {
            try writer.writeAll("{\"kind\":\"cursor\",\"layout\":");
            try writeLayoutJson(writer, makeFrame(origin, size));
            try writer.writeAll(",\"tone\":");
            try writeJsonEnumTag(writer, cursor_node.tone);
            try writer.writeByte('}');
        },
        .stack => |stack_node| {
            try writer.writeAll("{\"kind\":");
            try writeJsonString(writer, if (stack_node.axis == .horizontal) "row" else "column");
            try writer.writeAll(",\"layout\":");
            try writeLayoutJson(writer, makeFrame(origin, size));
            try writer.writeAll(",\"gap\":");
            try writeJsonNumber(writer, stack_node.gap);
            try writer.writeAll(",\"children\":[");

            const children = tree.childrenFor(stack_node.children);
            var child_origin = origin;
            for (children, 0..) |child_id, index| {
                if (index > 0) try writer.writeByte(',');
                try writeNodeJsonAt(tree, writer, child_id, child_origin);

                const child_size = measureNode(tree, child_id);
                switch (stack_node.axis) {
                    .horizontal => child_origin.x += child_size.width + stack_node.gap,
                    .vertical => child_origin.y += child_size.height + stack_node.gap,
                }
            }

            try writer.writeAll("]}");
        },
        .box => |box_node| {
            const child_size = measureNode(tree, box_node.child);
            try writer.writeAll("{\"kind\":\"box\",\"title\":");
            if (box_node.title) |title| {
                try writeJsonString(writer, title);
            } else {
                try writer.writeAll("null");
            }
            try writer.writeAll(",\"region\":");
            if (box_node.region) |region| {
                try writeJsonString(writer, region);
            } else {
                try writer.writeAll("null");
            }
            try writer.writeAll(",\"action\":");
            if (box_node.action) |action| {
                try writeActionJson(writer, action);
            } else {
                try writer.writeAll("null");
            }
            try writer.writeAll(",\"layout\":");
            try writeLayoutJson(writer, makeFrame(origin, size));
            try writer.writeAll(",\"tone\":");
            try writeJsonEnumTag(writer, box_node.tone);
            try writer.writeAll(",\"alignment\":");
            try writeJsonEnumTag(writer, box_node.alignment);
            try writer.writeAll(",\"border\":");
            try writeJsonEnumTag(writer, box_node.border);
            try writer.writeAll(",\"padding\":");
            try writeInsetsJson(writer, box_node.padding);
            try writer.writeAll(",\"child\":");
            try writeNodeJsonAt(tree, writer, box_node.child, boxChildOrigin(origin, box_node, child_size));
            try writer.writeByte('}');
        },
        .spacer => |spacer_node| {
            try writer.writeAll("{\"kind\":\"spacer\",\"layout\":");
            try writeLayoutJson(writer, makeFrame(origin, size));
            try writer.writeAll(",\"width\":");
            try writeJsonNumber(writer, spacer_node.width);
            try writer.writeAll(",\"height\":");
            try writeJsonNumber(writer, spacer_node.height);
            try writer.writeByte('}');
        },
        .rule => |rule_node| {
            var glyph_buffer: [4]u8 = undefined;
            const glyph_len = std.unicode.utf8Encode(rule_node.glyph, &glyph_buffer) catch unreachable;

            try writer.writeAll("{\"kind\":\"rule\",\"layout\":");
            try writeLayoutJson(writer, makeFrame(origin, size));
            try writer.writeAll(",\"width\":");
            try writeJsonNumber(writer, rule_node.width);
            try writer.writeAll(",\"glyph\":");
            try writeJsonString(writer, glyph_buffer[0..glyph_len]);
            try writer.writeAll(",\"tone\":");
            try writeJsonEnumTag(writer, rule_node.tone);
            try writer.writeByte('}');
        },
    }
}

// Stringifies one enum tag using its stable source-level name.
fn writeJsonEnumTag(writer: anytype, value: anytype) !void {
    try writeJsonString(writer, @tagName(value));
}

// Writes a JSON string with the standard escaping rules.
fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');

    for (value) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x08 => try writer.writeAll("\\b"),
            0x0c => try writer.writeAll("\\f"),
            else => {
                if (byte < 0x20) {
                    var escape: [6]u8 = undefined;
                    const slice = try std.fmt.bufPrint(&escape, "\\u00{x:0>2}", .{byte});
                    try writer.writeAll(slice);
                } else {
                    try writer.writeByte(byte);
                }
            },
        }
    }

    try writer.writeByte('"');
}

// Writes an unsigned JSON number.
fn writeJsonNumber(writer: anytype, value: usize) !void {
    try std.fmt.format(writer, "{d}", .{value});
}

// Serializes one interactive action target for browser hosts.
fn writeActionJson(writer: anytype, action: Action) !void {
    try writer.writeAll("{\"kind\":");
    try writeJsonString(writer, action.kind);
    try writer.writeAll(",\"value\":");
    try writeJsonNumber(writer, action.value);
    try writer.writeByte('}');
}

// Serializes one measured node frame.
fn writeLayoutJson(writer: anytype, frame: LayoutFrame) !void {
    try writer.writeAll("{\"x\":");
    try writeJsonNumber(writer, frame.x);
    try writer.writeAll(",\"y\":");
    try writeJsonNumber(writer, frame.y);
    try writer.writeAll(",\"width\":");
    try writeJsonNumber(writer, frame.width);
    try writer.writeAll(",\"height\":");
    try writeJsonNumber(writer, frame.height);
    try writer.writeByte('}');
}

// Serializes box padding explicitly so browser hosts can keep spacing intent.
fn writeInsetsJson(writer: anytype, insets: Insets) !void {
    try writer.writeAll("{\"top\":");
    try writeJsonNumber(writer, insets.top);
    try writer.writeAll(",\"right\":");
    try writeJsonNumber(writer, insets.right);
    try writer.writeAll(",\"bottom\":");
    try writeJsonNumber(writer, insets.bottom);
    try writer.writeAll(",\"left\":");
    try writeJsonNumber(writer, insets.left);
    try writer.writeByte('}');
}

// Packs an origin and measured size into one serializable frame.
fn makeFrame(origin: LayoutOrigin, size: LayoutSize) LayoutFrame {
    return .{
        .x = origin.x,
        .y = origin.y,
        .width = size.width,
        .height = size.height,
    };
}

// Measures one node without allocating render buffers so non-terminal hosts can
// reason about the same layout as the text renderer.
fn measureNode(tree: *const Tree, node_id: NodeId) LayoutSize {
    return switch (tree.nodes.items[node_id]) {
        .text => |text_node| measureTextContent(text_node.content),
        .cursor => .{ .width = 0, .height = 1 },
        .stack => |stack_node| measureStack(tree, stack_node),
        .box => |box_node| measureBox(box_node, measureNode(tree, box_node.child)),
        .spacer => |spacer_node| .{
            .width = spacer_node.width,
            .height = spacerHeight(spacer_node),
        },
        .rule => |rule_node| .{
            .width = ruleWidth(rule_node),
            .height = 1,
        },
    };
}

// Text nodes expand to the widest rendered line and keep at least one row.
fn measureTextContent(text: []const u8) LayoutSize {
    var width: usize = 0;
    var height: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');

    while (lines.next()) |part| {
        height += 1;
        width = @max(width, displayWidth(part));
    }

    if (height == 0) height = 1;
    return .{ .width = width, .height = height };
}

// Stacks resolve to the same rectangular size used by the line renderer.
fn measureStack(tree: *const Tree, stack_node: StackNode) LayoutSize {
    const children = tree.childrenFor(stack_node.children);
    if (children.len == 0) {
        return .{ .width = 0, .height = 1 };
    }

    return switch (stack_node.axis) {
        .vertical => blk: {
            var width: usize = 0;
            var height: usize = 0;

            for (children, 0..) |child_id, index| {
                const child = measureNode(tree, child_id);
                width = @max(width, child.width);
                height += child.height;
                if (index + 1 < children.len) {
                    height += stack_node.gap;
                }
            }

            break :blk .{ .width = width, .height = height };
        },
        .horizontal => blk: {
            var width: usize = 0;
            var height: usize = 0;

            for (children, 0..) |child_id, index| {
                const child = measureNode(tree, child_id);
                width += child.width;
                if (index + 1 < children.len) {
                    width += stack_node.gap;
                }
                height = @max(height, child.height);
            }

            break :blk .{ .width = width, .height = height };
        },
    };
}

// Box size is derived from child size, padding, optional title span, and
// border cells so renderer and browser host share the same contract.
fn measureBox(box_node: BoxNode, child: LayoutSize) LayoutSize {
    const body_width = measureBoxBodyWidth(box_node, child.width);
    const border_cells = borderInset(box_node.border) * 2;
    return .{
        .width = body_width + border_cells,
        .height = child.height + box_node.padding.top + box_node.padding.bottom + border_cells,
    };
}

// The title is embedded into the top border, so it can widen the whole box.
fn measureBoxBodyWidth(box_node: BoxNode, child_width: usize) usize {
    const title_width = if (box_node.title) |title| displayWidth(title) + 2 else 0;
    const padded_child_width = child_width + box_node.padding.left + box_node.padding.right;
    return @max(padded_child_width, title_width);
}

// Box children are placed inside the border and padding, with the same
// alignment math used by the text renderer.
fn boxChildOrigin(origin: LayoutOrigin, box_node: BoxNode, child: LayoutSize) LayoutOrigin {
    const body_width = measureBoxBodyWidth(box_node, child.width);
    const inner_width = body_width - box_node.padding.left - box_node.padding.right;
    const left_offset = alignedOffset(box_node.alignment, inner_width, child.width);
    const inset = borderInset(box_node.border);

    return .{
        .x = origin.x + inset + box_node.padding.left + left_offset,
        .y = origin.y + inset + box_node.padding.top,
    };
}

// Horizontal alignment offset shared by box layout and line rendering.
fn alignedOffset(alignment: Align, width: usize, child_width: usize) usize {
    const remaining = width - child_width;
    return switch (alignment) {
        .left => 0,
        .center => remaining / 2,
        .right => remaining,
    };
}

// Border thickness expressed in terminal cells.
fn borderInset(border: Border) usize {
    return switch (border) {
        .none => 0,
        .single => 1,
    };
}

// Spacers keep at least one row so they remain visible to hosts.
fn spacerHeight(spacer_node: SpacerNode) usize {
    return if (spacer_node.height == 0) 1 else spacer_node.height;
}

// Rules keep at least one column, matching the renderer.
fn ruleWidth(rule_node: RuleNode) usize {
    return if (rule_node.width == 0) 1 else rule_node.width;
}

// One rendered line plus its cached display width.
const Line = struct {
    bytes: std.ArrayList(u8) = .empty,
    width: usize = 0,

    fn deinit(self: *Line, allocator: std.mem.Allocator) void {
        self.bytes.deinit(allocator);
    }

    fn appendSlice(self: *Line, allocator: std.mem.Allocator, text: []const u8) !void {
        try self.bytes.appendSlice(allocator, text);
        self.width += displayWidth(text);
    }

    fn appendStyledSlice(self: *Line, allocator: std.mem.Allocator, text: []const u8, tone: Tone) !void {
        try self.appendStyledSliceWithMode(allocator, text, tone, true);
    }

    fn appendStyledSliceWithMode(self: *Line, allocator: std.mem.Allocator, text: []const u8, tone: Tone, ansi: bool) !void {
        if (!ansi or tone == .normal) {
            try self.appendSlice(allocator, text);
            return;
        }

        try self.bytes.appendSlice(allocator, tonePrefix(tone));
        try self.bytes.appendSlice(allocator, text);
        try self.bytes.appendSlice(allocator, ansi_reset);
        self.width += displayWidth(text);
    }

    fn appendRepeat(self: *Line, allocator: std.mem.Allocator, value: u8, count: usize) !void {
        if (count == 0) return;
        const slice = try self.bytes.addManyAsSlice(allocator, count);
        @memset(slice, value);
        self.width += count;
    }

    fn appendStyledRepeat(self: *Line, allocator: std.mem.Allocator, value: u8, count: usize, tone: Tone) !void {
        try self.appendStyledRepeatWithMode(allocator, value, count, tone, true);
    }

    fn appendStyledRepeatWithMode(self: *Line, allocator: std.mem.Allocator, value: u8, count: usize, tone: Tone, ansi: bool) !void {
        if (count == 0) return;
        if (!ansi or tone == .normal) {
            try self.appendRepeat(allocator, value, count);
            return;
        }

        try self.bytes.appendSlice(allocator, tonePrefix(tone));
        const slice = try self.bytes.addManyAsSlice(allocator, count);
        @memset(slice, value);
        try self.bytes.appendSlice(allocator, ansi_reset);
        self.width += count;
    }

    fn appendLine(self: *Line, allocator: std.mem.Allocator, source: *const Line) !void {
        try self.bytes.appendSlice(allocator, source.bytes.items);
        self.width += source.width;
    }
};

// Intermediate block used by the tree renderer before the host consumes bytes.
const Block = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList(Line) = .empty,
    width: usize = 0,
    cursor: ?Cursor = null,

    fn init(allocator: std.mem.Allocator) Block {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *Block) void {
        for (self.lines.items) |*line| {
            line.deinit(self.allocator);
        }
        self.lines.deinit(self.allocator);
    }

    fn height(self: *const Block) usize {
        return self.lines.items.len;
    }

    fn appendEmptyLine(self: *Block) !*Line {
        try self.lines.append(self.allocator, .{});
        return &self.lines.items[self.lines.items.len - 1];
    }

    fn appendBlankLine(self: *Block, width: usize) !void {
        var line = Line{};
        try line.appendRepeat(self.allocator, ' ', width);
        try self.lines.append(self.allocator, line);
        self.width = @max(self.width, width);
    }

    fn writeTo(self: *const Block, writer: anytype) !void {
        for (self.lines.items, 0..) |line, index| {
            try writer.writeAll(line.bytes.items);
            if (index + 1 < self.lines.items.len) {
                try writer.writeByte('\n');
            }
        }
    }
};

// Rendering currently only needs to know whether ANSI styling is enabled.
const RenderContext = struct {
    ansi: bool,
};

// Dispatches node rendering by variant.
fn renderNode(tree: *Tree, node_id: NodeId, ctx: RenderContext) std.mem.Allocator.Error!Block {
    const allocator = tree.allocator();
    return switch (tree.nodes.items[node_id]) {
        .text => |text_node| try renderText(allocator, text_node, ctx),
        .cursor => |cursor_node| try renderCursor(allocator, cursor_node, ctx),
        .stack => |stack_node| try renderStack(tree, stack_node, ctx),
        .box => |box_node| try renderBox(tree, box_node, ctx),
        .spacer => |spacer_node| try renderSpacer(allocator, spacer_node),
        .rule => |rule_node| try renderRule(allocator, rule_node, ctx),
    };
}

// Splits a text node into one or more rendered lines.
fn renderText(allocator: std.mem.Allocator, text_node: TextNode, ctx: RenderContext) std.mem.Allocator.Error!Block {
    var block = Block.init(allocator);
    var lines = std.mem.splitScalar(u8, text_node.content, '\n');
    while (lines.next()) |part| {
        const line = try block.appendEmptyLine();
        try line.appendStyledSliceWithMode(allocator, part, text_node.tone, ctx.ansi);
        block.width = @max(block.width, line.width);
    }

    if (block.lines.items.len == 0) {
        _ = try block.appendEmptyLine();
    }

    return block;
}

// Cursor nodes render semantically: plain hosts get `|`, terminal hosts get a
// solid block so the caret is not mistaken for model text.
fn renderCursor(allocator: std.mem.Allocator, cursor_node: CursorNode, ctx: RenderContext) std.mem.Allocator.Error!Block {
    var block = Block.init(allocator);

    if (ctx.ansi) {
        _ = try block.appendEmptyLine();
        block.cursor = .{ .x = 0, .y = 0 };
        block.width = 0;
        return block;
    }

    var line = Line{};
    try line.appendStyledSliceWithMode(allocator, "|", cursor_node.tone, false);
    block.width = 1;
    try block.lines.append(allocator, line);
    return block;
}

// Spacers produce blank rectangular blocks.
fn renderSpacer(allocator: std.mem.Allocator, spacer_node: SpacerNode) std.mem.Allocator.Error!Block {
    var block = Block.init(allocator);
    block.width = spacer_node.width;

    const height = spacerHeight(spacer_node);
    for (0..height) |_| {
        try block.appendBlankLine(spacer_node.width);
    }

    return block;
}

// Rules repeat one glyph across a single line.
fn renderRule(allocator: std.mem.Allocator, rule_node: RuleNode, ctx: RenderContext) std.mem.Allocator.Error!Block {
    var block = Block.init(allocator);
    const width = ruleWidth(rule_node);
    var line = Line{};

    if (rule_node.glyph <= 0x7F) {
        try line.appendStyledRepeatWithMode(allocator, @intCast(rule_node.glyph), width, rule_node.tone, ctx.ansi);
    } else {
        const glyph = try std.fmt.allocPrint(allocator, "{u}", .{rule_node.glyph});
        for (0..width) |_| {
            try line.appendStyledSliceWithMode(allocator, glyph, rule_node.tone, ctx.ansi);
        }
    }

    block.width = width;
    try block.lines.append(allocator, line);
    return block;
}

// Rows and columns are laid out eagerly into rectangular blocks.
fn renderStack(tree: *Tree, stack_node: StackNode, ctx: RenderContext) std.mem.Allocator.Error!Block {
    const allocator = tree.allocator();
    var block = Block.init(allocator);
    const children = tree.childrenFor(stack_node.children);

    if (children.len == 0) {
        _ = try block.appendEmptyLine();
        return block;
    }

    var rendered = std.ArrayList(Block).empty;
    defer {
        for (rendered.items) |*child_block| {
            child_block.deinit();
        }
        rendered.deinit(allocator);
    }

    for (children) |child_id| {
        try rendered.append(allocator, try renderNode(tree, child_id, ctx));
    }

    switch (stack_node.axis) {
        .vertical => {
            for (rendered.items, 0..) |*child_block, index| {
                block.width = @max(block.width, child_block.width);
                if (index > 0) {
                    for (0..stack_node.gap) |_| {
                        try block.appendBlankLine(block.width);
                    }
                }
                if (child_block.cursor) |cursor| {
                    block.cursor = .{
                        .x = cursor.x,
                        .y = block.lines.items.len + cursor.y,
                    };
                }
                for (child_block.lines.items) |*child_line| {
                    var line = Line{};
                    try line.appendLine(allocator, child_line);
                    try line.appendRepeat(allocator, ' ', block.width - child_line.width);
                    try block.lines.append(allocator, line);
                }
            }

            if (block.lines.items.len == 0) {
                _ = try block.appendEmptyLine();
            }
        },
        .horizontal => {
            var total_width: usize = 0;
            var max_height: usize = 0;
            var cursor_x: usize = 0;
            for (rendered.items, 0..) |child_block, index| {
                total_width += child_block.width;
                if (index + 1 < rendered.items.len) {
                    total_width += stack_node.gap;
                }
                max_height = @max(max_height, child_block.height());
                if (child_block.cursor) |cursor| {
                    block.cursor = .{
                        .x = cursor_x + cursor.x,
                        .y = cursor.y,
                    };
                }
                cursor_x += child_block.width;
                if (index + 1 < rendered.items.len) {
                    cursor_x += stack_node.gap;
                }
            }

            block.width = total_width;

            for (0..max_height) |row_index| {
                var line = Line{};
                for (rendered.items, 0..) |*child_block, child_index| {
                    if (row_index < child_block.lines.items.len) {
                        const child_line = &child_block.lines.items[row_index];
                        try line.appendLine(allocator, child_line);
                        try line.appendRepeat(allocator, ' ', child_block.width - child_line.width);
                    } else {
                        try line.appendRepeat(allocator, ' ', child_block.width);
                    }
                    if (child_index + 1 < rendered.items.len) {
                        try line.appendRepeat(allocator, ' ', stack_node.gap);
                    }
                }
                try block.lines.append(allocator, line);
            }

            if (block.lines.items.len == 0) {
                _ = try block.appendEmptyLine();
            }
        },
    }

    return block;
}

// Boxes wrap an inner block with optional borders, padding, and a title row.
fn renderBox(tree: *Tree, box_node: BoxNode, ctx: RenderContext) std.mem.Allocator.Error!Block {
    const allocator = tree.allocator();
    var child_block = try renderNode(tree, box_node.child, ctx);
    defer child_block.deinit();

    const title_width = if (box_node.title) |title| displayWidth(title) + 2 else 0;
    const body_width = measureBoxBodyWidth(box_node, child_block.width);

    var block = Block.init(allocator);
    block.width = measureBox(box_node, .{
        .width = child_block.width,
        .height = child_block.height(),
    }).width;

    if (box_node.border == .single) {
        var top = Line{};
        try top.appendStyledRepeatWithMode(allocator, '+', 1, box_node.tone, ctx.ansi);
        if (box_node.title) |title| {
            try top.appendStyledRepeatWithMode(allocator, ' ', 1, box_node.tone, ctx.ansi);
            try top.appendStyledSliceWithMode(allocator, title, box_node.tone, ctx.ansi);
            try top.appendStyledRepeatWithMode(allocator, ' ', 1, box_node.tone, ctx.ansi);
            try top.appendStyledRepeatWithMode(allocator, '-', body_width - title_width, box_node.tone, ctx.ansi);
        } else {
            try top.appendStyledRepeatWithMode(allocator, '-', body_width, box_node.tone, ctx.ansi);
        }
        try top.appendStyledRepeatWithMode(allocator, '+', 1, box_node.tone, ctx.ansi);
        try block.lines.append(allocator, top);
    }

    for (0..box_node.padding.top) |_| {
        try appendBoxLine(&block, body_width, null, box_node.padding.left, box_node.padding.right, box_node.border, box_node.alignment, box_node.tone, ctx);
    }

    const inner_width = body_width - box_node.padding.left - box_node.padding.right;
    const child_left_offset = alignedOffset(box_node.alignment, inner_width, child_block.width);
    if (child_block.cursor) |cursor| {
        const inset = borderInset(box_node.border);
        block.cursor = .{
            .x = inset + box_node.padding.left + child_left_offset + cursor.x,
            .y = inset + box_node.padding.top + cursor.y,
        };
    }
    for (child_block.lines.items) |*child_line| {
        try appendBoxLine(&block, inner_width, child_line, box_node.padding.left, box_node.padding.right, box_node.border, box_node.alignment, box_node.tone, ctx);
    }

    if (child_block.lines.items.len == 0) {
        try appendBoxLine(&block, inner_width, null, box_node.padding.left, box_node.padding.right, box_node.border, box_node.alignment, box_node.tone, ctx);
    }

    for (0..box_node.padding.bottom) |_| {
        try appendBoxLine(&block, body_width, null, box_node.padding.left, box_node.padding.right, box_node.border, box_node.alignment, box_node.tone, ctx);
    }

    if (box_node.border == .single) {
        var bottom = Line{};
        try bottom.appendStyledRepeatWithMode(allocator, '+', 1, box_node.tone, ctx.ansi);
        try bottom.appendStyledRepeatWithMode(allocator, '-', body_width, box_node.tone, ctx.ansi);
        try bottom.appendStyledRepeatWithMode(allocator, '+', 1, box_node.tone, ctx.ansi);
        try block.lines.append(allocator, bottom);
    }

    return block;
}

// Appends one padded content line inside a box.
fn appendBoxLine(
    block: *Block,
    inner_width: usize,
    child_line: ?*const Line,
    pad_left: usize,
    pad_right: usize,
    border: Border,
    alignment: Align,
    tone: Tone,
    ctx: RenderContext,
) std.mem.Allocator.Error!void {
    var line = Line{};
    if (border == .single) {
        try line.appendStyledRepeatWithMode(block.allocator, '|', 1, tone, ctx.ansi);
    }

    try line.appendRepeat(block.allocator, ' ', pad_left);
    try appendAlignedLine(&line, block.allocator, child_line, inner_width, alignment);
    try line.appendRepeat(block.allocator, ' ', pad_right);

    if (border == .single) {
        try line.appendStyledRepeatWithMode(block.allocator, '|', 1, tone, ctx.ansi);
    }

    try block.lines.append(block.allocator, line);
}

// Aligns a child line inside a fixed-width slot.
fn appendAlignedLine(
    target: *Line,
    allocator: std.mem.Allocator,
    child_line: ?*const Line,
    width: usize,
    alignment: Align,
) std.mem.Allocator.Error!void {
    if (child_line == null) {
        try target.appendRepeat(allocator, ' ', width);
        return;
    }

    const line = child_line.?;
    const left_padding = alignedOffset(alignment, width, line.width);
    const remaining = width - line.width;
    const right_padding = remaining - left_padding;

    try target.appendRepeat(allocator, ' ', left_padding);
    try target.appendLine(allocator, line);
    try target.appendRepeat(allocator, ' ', right_padding);
}

// Reset sequence appended after styled spans.
const ansi_reset = "\x1b[0m";

// Maps semantic tones to ANSI color/style prefixes.
fn tonePrefix(tone: Tone) []const u8 {
    return switch (tone) {
        .normal => "",
        .muted => "\x1b[90m",
        .accent => "\x1b[1;96m",
        .success => "\x1b[1;92m",
        .warning => "\x1b[1;93m",
    };
}

test "tree renders panels and rows" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    const title = try tree.textStyled("Framework", .{ .tone = .accent });
    const status = try tree.text("Headless first");
    const row = try tree.row(&.{ title, status }, .{ .gap = 2 });
    const panel = try tree.box(row, .{
        .title = "Demo",
        .padding = Insets.symmetric(0, 1),
        .tone = .accent,
    });

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    const writer = buffer.writer(std.testing.allocator);
    try tree.render(writer, panel, .{ .ansi = true });

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "Framework") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "Headless first") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "Demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\x1b[") != null);
}

test "tree can render without ansi escapes" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    const text = try tree.textStyled("plain", .{ .tone = .accent });
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    try tree.render(buffer.writer(std.testing.allocator), text, .{ .ansi = false });
    try std.testing.expectEqualStrings("plain", buffer.items);
}

test "tree writes structured json snapshots" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    const left = try tree.textStyled("ab", .{ .tone = .accent });
    const right = try tree.text("cd");
    const row = try tree.box(
        try tree.row(&.{ left, right }, .{ .gap = 3 }),
        .{
            .title = "Row",
            .region = "list",
            .action = .{
                .kind = "select_row",
                .value = 1,
            },
            .padding = Insets.symmetric(0, 1),
        },
    );

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    try tree.writeJson(buffer.writer(std.testing.allocator), row);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"kind\":\"box\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"region\":\"list\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"action\":{\"kind\":\"select_row\",\"value\":1}") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"kind\":\"row\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"layout\":{\"x\":0,\"y\":0,\"width\":11,\"height\":3}") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"layout\":{\"x\":7,\"y\":1,\"width\":2,\"height\":1}") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"tone\":\"accent\"") != null);
}

test "renderModelJson falls back to plain text view models" {
    const Model = struct {
        pub fn view(_: *const @This(), writer: anytype) !void {
            try writer.writeAll("plain fallback");
        }
    };

    var model = Model{};
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    try renderModelJson(Model, std.testing.allocator, &model, buffer.writer(std.testing.allocator));

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"kind\":\"text\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"layout\":{\"x\":0,\"y\":0,\"width\":14,\"height\":1}") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "plain fallback") != null);
}
