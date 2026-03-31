const std = @import("std");

pub const NodeId = u32;

pub const Axis = enum {
    horizontal,
    vertical,
};

pub const Border = enum {
    none,
    single,
};

pub const Tone = enum {
    normal,
    muted,
    accent,
    success,
    warning,
};

pub const Align = enum {
    left,
    center,
    right,
};

pub const Insets = struct {
    top: usize = 0,
    right: usize = 0,
    bottom: usize = 0,
    left: usize = 0,

    pub fn all(value: usize) Insets {
        return .{
            .top = value,
            .right = value,
            .bottom = value,
            .left = value,
        };
    }

    pub fn symmetric(vertical: usize, horizontal: usize) Insets {
        return .{
            .top = vertical,
            .right = horizontal,
            .bottom = vertical,
            .left = horizontal,
        };
    }
};

pub const TextOptions = struct {
    alignment: Align = .left,
    tone: Tone = .normal,
};

pub const StackOptions = struct {
    gap: usize = 0,
};

pub const BoxOptions = struct {
    title: ?[]const u8 = null,
    padding: Insets = .{},
    border: Border = .single,
    alignment: Align = .left,
    tone: Tone = .normal,
};

pub const RuleOptions = struct {
    tone: Tone = .muted,
    glyph: u21 = '-',
};

pub const RenderOptions = struct {
    ansi: bool = true,
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

const StackNode = struct {
    axis: Axis,
    children: ChildRange,
    gap: usize,
};

const BoxNode = struct {
    child: NodeId,
    title: ?[]const u8,
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
    stack: StackNode,
    box: BoxNode,
    spacer: SpacerNode,
    rule: RuleNode,
};

pub const Tree = struct {
    arena_state: std.heap.ArenaAllocator,
    nodes: std.ArrayList(Node) = .empty,
    children: std.ArrayList(NodeId) = .empty,

    pub fn init(parent_allocator: std.mem.Allocator) Tree {
        return .{
            .arena_state = std.heap.ArenaAllocator.init(parent_allocator),
        };
    }

    pub fn deinit(self: *Tree) void {
        const arena = self.allocator();
        self.children.deinit(arena);
        self.nodes.deinit(arena);
        self.arena_state.deinit();
    }

    pub fn allocator(self: *Tree) std.mem.Allocator {
        return self.arena_state.allocator();
    }

    pub fn allocNodeIds(self: *Tree, count: usize) ![]NodeId {
        return self.allocator().alloc(NodeId, count);
    }

    pub fn text(self: *Tree, content: []const u8) !NodeId {
        return self.textStyled(content, .{});
    }

    pub fn textStyled(self: *Tree, content: []const u8, options: TextOptions) !NodeId {
        return self.appendNode(.{
            .text = .{
                .content = content,
                .alignment = options.alignment,
                .tone = options.tone,
            },
        });
    }

    pub fn format(self: *Tree, comptime fmt: []const u8, args: anytype) !NodeId {
        const content = try std.fmt.allocPrint(self.allocator(), fmt, args);
        return self.text(content);
    }

    pub fn row(self: *Tree, children: []const NodeId, options: StackOptions) !NodeId {
        return self.stack(.horizontal, children, options);
    }

    pub fn column(self: *Tree, children: []const NodeId, options: StackOptions) !NodeId {
        return self.stack(.vertical, children, options);
    }

    pub fn stack(self: *Tree, axis: Axis, children: []const NodeId, options: StackOptions) !NodeId {
        return self.appendNode(.{
            .stack = .{
                .axis = axis,
                .children = try self.appendChildren(children),
                .gap = options.gap,
            },
        });
    }

    pub fn box(self: *Tree, child: NodeId, options: BoxOptions) !NodeId {
        return self.appendNode(.{
            .box = .{
                .child = child,
                .title = options.title,
                .padding = options.padding,
                .border = options.border,
                .alignment = options.alignment,
                .tone = options.tone,
            },
        });
    }

    pub fn spacer(self: *Tree, width: usize, height: usize) !NodeId {
        return self.appendNode(.{
            .spacer = .{
                .width = width,
                .height = height,
            },
        });
    }

    pub fn rule(self: *Tree, width: usize, options: RuleOptions) !NodeId {
        return self.appendNode(.{
            .rule = .{
                .width = width,
                .glyph = options.glyph,
                .tone = options.tone,
            },
        });
    }

    pub fn render(self: *Tree, writer: anytype, root: NodeId, options: RenderOptions) !void {
        var block = try renderNode(self, root, .{ .ansi = options.ansi });
        defer block.deinit();
        try block.writeTo(writer);
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

pub fn renderModel(
    comptime ModelType: type,
    allocator: std.mem.Allocator,
    model: *const ModelType,
    frame_buffer: *std.ArrayList(u8),
    options: RenderOptions,
) !void {
    frame_buffer.clearRetainingCapacity();

    if (@hasDecl(ModelType, "compose")) {
        var tree = Tree.init(allocator);
        defer tree.deinit();

        const root = try model.compose(&tree);
        const writer = frame_buffer.writer(allocator);
        try tree.render(writer, root, options);
        return;
    }

    if (@hasDecl(ModelType, "view")) {
        const writer = frame_buffer.writer(allocator);
        try model.view(writer);
        return;
    }

    @compileError("ModelType must declare either compose(self: *const ModelType, tree: *ui.Tree) !ui.NodeId or view(self: *const ModelType, writer: anytype) !void");
}

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

const Block = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList(Line) = .empty,
    width: usize = 0,

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

const RenderContext = struct {
    ansi: bool,
};

fn renderNode(tree: *Tree, node_id: NodeId, ctx: RenderContext) std.mem.Allocator.Error!Block {
    const allocator = tree.allocator();
    return switch (tree.nodes.items[node_id]) {
        .text => |text_node| try renderText(allocator, text_node, ctx),
        .stack => |stack_node| try renderStack(tree, stack_node, ctx),
        .box => |box_node| try renderBox(tree, box_node, ctx),
        .spacer => |spacer_node| try renderSpacer(allocator, spacer_node),
        .rule => |rule_node| try renderRule(allocator, rule_node, ctx),
    };
}

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

fn renderSpacer(allocator: std.mem.Allocator, spacer_node: SpacerNode) std.mem.Allocator.Error!Block {
    var block = Block.init(allocator);
    block.width = spacer_node.width;

    const height = if (spacer_node.height == 0) 1 else spacer_node.height;
    for (0..height) |_| {
        try block.appendBlankLine(spacer_node.width);
    }

    return block;
}

fn renderRule(allocator: std.mem.Allocator, rule_node: RuleNode, ctx: RenderContext) std.mem.Allocator.Error!Block {
    var block = Block.init(allocator);
    const width = if (rule_node.width == 0) 1 else rule_node.width;
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
            for (rendered.items, 0..) |child_block, index| {
                total_width += child_block.width;
                if (index + 1 < rendered.items.len) {
                    total_width += stack_node.gap;
                }
                max_height = @max(max_height, child_block.height());
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

fn renderBox(tree: *Tree, box_node: BoxNode, ctx: RenderContext) std.mem.Allocator.Error!Block {
    const allocator = tree.allocator();
    var child_block = try renderNode(tree, box_node.child, ctx);
    defer child_block.deinit();

    const title_width = if (box_node.title) |title| displayWidth(title) + 2 else 0;
    const padded_child_width = child_block.width + box_node.padding.left + box_node.padding.right;
    const body_width = @max(padded_child_width, title_width);

    var block = Block.init(allocator);
    block.width = switch (box_node.border) {
        .none => body_width,
        .single => body_width + 2,
    };

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
    const remaining = width - line.width;
    const left_padding = switch (alignment) {
        .left => 0,
        .center => remaining / 2,
        .right => remaining,
    };
    const right_padding = remaining - left_padding;

    try target.appendRepeat(allocator, ' ', left_padding);
    try target.appendLine(allocator, line);
    try target.appendRepeat(allocator, ' ', right_padding);
}

fn displayWidth(text: []const u8) usize {
    return std.unicode.utf8CountCodepoints(text) catch text.len;
}

const ansi_reset = "\x1b[0m";

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
