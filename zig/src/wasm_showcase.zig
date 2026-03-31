const std = @import("std");
const tea = @import("bubbletea_zig");
const showcase = tea.apps.showcase;

pub const std_options: std.Options = .{
    .page_size_min = 64 * 1024,
    .page_size_max = 64 * 1024,
};

const Msg = tea.Message(void);
const App = showcase.App(Msg);
const Program = tea.HeadlessProgram(App, void);
const allocator = std.heap.wasm_allocator;

var program: ?Program = null;
var render_buffer: std.ArrayList(u8) = .empty;

pub export fn bt_init() bool {
    if (program != null) return refreshRenderBuffer();

    program = Program.init(allocator, .{});
    _ = bt_resize(80, 24);
    return refreshRenderBuffer();
}

pub export fn bt_deinit() void {
    if (program) |*p| {
        p.deinit();
        program = null;
    }
    render_buffer.deinit(allocator);
    render_buffer = .empty;
}

pub export fn bt_resize(width: u16, height: u16) bool {
    const p = getProgram() orelse return false;
    p.send(.{
        .resize = .{
            .width = width,
            .height = height,
        },
    }) catch return false;
    _ = p.drain() catch return false;
    return refreshRenderBuffer();
}

pub export fn bt_send_key(code: u32) bool {
    const p = getProgram() orelse return false;
    p.send(.{ .key = decodeKey(code) }) catch return false;
    _ = p.drain() catch return false;
    return refreshRenderBuffer();
}

pub export fn bt_tick(delta_ms: u32) bool {
    const p = getProgram() orelse return false;
    _ = p.advanceBy(@as(u64, delta_ms) * std.time.ns_per_ms) catch return false;
    return refreshRenderBuffer();
}

pub export fn bt_render_ptr() [*]const u8 {
    _ = refreshRenderBuffer();
    return render_buffer.items.ptr;
}

pub export fn bt_render_len() usize {
    _ = refreshRenderBuffer();
    return render_buffer.items.len;
}

fn getProgram() ?*Program {
    if (program == null) {
        program = Program.init(allocator, .{});
        const p = &program.?;
        p.boot() catch return null;
        p.send(.{
            .resize = .{
                .width = 80,
                .height = 24,
            },
        }) catch return null;
        _ = p.drain() catch return null;
    }
    return &program.?;
}

fn refreshRenderBuffer() bool {
    const p = getProgram() orelse return false;
    render_buffer.clearRetainingCapacity();
    const writer = render_buffer.writer(allocator);
    p.render(writer) catch return false;
    return true;
}

fn decodeKey(code: u32) tea.Key {
    return switch (code) {
        3 => .ctrl_c,
        1001 => .up,
        1002 => .down,
        1003 => .left,
        1004 => .right,
        9 => .tab,
        13 => .enter,
        27 => .escape,
        127 => .backspace,
        else => if (code >= 32 and code < 0x110000)
            .{ .character = @intCast(code) }
        else
            .{ .unknown = @intCast(@min(code, 255)) },
    };
}
