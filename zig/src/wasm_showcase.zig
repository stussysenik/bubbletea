const std = @import("std");
const tea = @import("bubbletea_zig");
const showcase = tea.apps.showcase;

/// WASM page-size constraints keep the freestanding build predictable.
pub const std_options: std.Options = .{
    .page_size_min = 64 * 1024,
    .page_size_max = 64 * 1024,
};

const Msg = tea.Message(void);
const App = showcase.App(Msg);
const Program = tea.HeadlessProgram(App, void);
const allocator = std.heap.wasm_allocator;
const input_capacity = 4096;

// Global host state kept alive across JS calls.
var program: ?Program = null;
var render_buffer: std.ArrayList(u8) = .empty;
// Structured UI snapshots let browser hosts render real DOM nodes from the
// Zig view tree while the raw text frame stays available for debugging.
var tree_buffer: std.ArrayList(u8) = .empty;
// Browser hosts can copy UTF-8 text into this scratch space before calling
// `bt_send_paste`.
var input_buffer: [input_capacity]u8 = [_]u8{0} ** input_capacity;

/// Initializes the headless showcase and produces the first frame.
pub export fn bt_init() bool {
    const first_init = program == null;
    const p = ensureProgram() orelse return false;

    if (first_init) {
        p.send(.{
            .resize = .{
                .width = 80,
                .height = 24,
            },
        }) catch return false;
        _ = p.drain() catch return false;
    }

    return refreshRenderBuffer();
}

/// Tears down the WASM-side runtime and frame buffer.
pub export fn bt_deinit() void {
    if (program) |*p| {
        p.deinit();
        program = null;
    }
    render_buffer.deinit(allocator);
    render_buffer = .empty;
    tree_buffer.deinit(allocator);
    tree_buffer = .empty;
}

/// Sends a resize message from the browser host.
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

/// Sends one normalized key code into the headless runtime.
pub export fn bt_send_key(code: u32) bool {
    const p = getProgram() orelse return false;
    p.send(.{ .key = decodeKey(code) }) catch return false;
    _ = p.drain() catch return false;
    return refreshRenderBuffer();
}

/// Returns a writable pointer to the shared UTF-8 input scratch buffer.
pub export fn bt_input_ptr() [*]u8 {
    return &input_buffer;
}

/// Returns the capacity of the shared UTF-8 input scratch buffer.
pub export fn bt_input_capacity() usize {
    return input_capacity;
}

/// Sends UTF-8 bytes from the shared scratch buffer as one paste event.
pub export fn bt_send_paste(len: usize) bool {
    if (len > input_capacity) return false;
    const text = input_buffer[0..len];
    if (!isValidUtf8(text)) return false;

    const p = getProgram() orelse return false;
    p.send(.{ .paste = text }) catch return false;
    _ = p.drain() catch return false;
    return refreshRenderBuffer();
}

/// Reports whether the browser host is focused, mirroring terminal focus
/// events.
pub export fn bt_set_focus(focused: bool) bool {
    const p = getProgram() orelse return false;
    p.send(if (focused) .focus_gained else .focus_lost) catch return false;
    _ = p.drain() catch return false;
    return refreshRenderBuffer();
}

/// Focuses one known showcase region directly from the browser host.
pub export fn bt_focus_region(region_code: u8) bool {
    const region = decodeRegion(region_code) orelse return false;
    const p = getProgram() orelse return false;

    _ = p.model.focusBrowserRegion(region);
    return refreshBuffers();
}

/// Invokes one browser-tagged showcase action directly from the web host.
pub export fn bt_send_action(action_code: u8, value: u16) bool {
    const action = decodeAction(action_code) orelse return false;
    const p = getProgram() orelse return false;

    if (!p.model.triggerBrowserAction(action, value)) return false;
    return refreshBuffers();
}

/// Sends one normalized mouse event from the browser host.
///
/// `button_code` maps to:
/// 0 none, 1 left, 2 middle, 3 right, 4 wheel_up, 5 wheel_down,
/// 6 wheel_left, 7 wheel_right.
///
/// `action_code` maps to:
/// 1 press, 2 release, 3 drag, 4 move, 5 scroll.
///
/// `modifiers` uses bit flags:
/// 1 shift, 2 alt, 4 ctrl.
pub export fn bt_send_mouse(button_code: u8, action_code: u8, x: u16, y: u16, modifiers: u8) bool {
    const button = decodeMouseButton(button_code) orelse return false;
    const action = decodeMouseAction(action_code) orelse return false;
    const p = getProgram() orelse return false;

    p.send(.{ .mouse = .{
        .x = x,
        .y = y,
        .button = button,
        .action = action,
        .modifiers = .{
            .shift = (modifiers & 1) != 0,
            .alt = (modifiers & 2) != 0,
            .ctrl = (modifiers & 4) != 0,
        },
    } }) catch return false;
    _ = p.drain() catch return false;
    return refreshRenderBuffer();
}

/// Advances timer state by a browser-provided delta.
pub export fn bt_tick(delta_ms: u32) bool {
    const p = getProgram() orelse return false;
    _ = p.advanceBy(@as(u64, delta_ms) * std.time.ns_per_ms) catch return false;
    return refreshBuffers();
}

/// Returns the start pointer for the current frame buffer.
pub export fn bt_render_ptr() [*]const u8 {
    _ = refreshRenderBuffer();
    return render_buffer.items.ptr;
}

/// Returns the current frame length in bytes.
pub export fn bt_render_len() usize {
    _ = refreshRenderBuffer();
    return render_buffer.items.len;
}

/// Returns the start pointer for the current structured UI snapshot.
pub export fn bt_tree_ptr() [*]const u8 {
    _ = refreshTreeBuffer();
    return tree_buffer.items.ptr;
}

/// Returns the current structured UI snapshot length in bytes.
pub export fn bt_tree_len() usize {
    _ = refreshTreeBuffer();
    return tree_buffer.items.len;
}

// Lazily boots the headless runtime on first use.
fn getProgram() ?*Program {
    return ensureProgram();
}

// Creates and boots the runtime exactly once, even when the browser host
// calls into exports in different orders.
fn ensureProgram() ?*Program {
    if (program == null) {
        program = Program.init(allocator, .{});
    }
    const p = &program.?;
    p.boot() catch return null;
    return &program.?;
}

// Re-renders the current frame into a buffer the JS host can read.
fn refreshRenderBuffer() bool {
    const p = getProgram() orelse return false;
    render_buffer.clearRetainingCapacity();
    const writer = render_buffer.writer(allocator);
    p.render(writer) catch return false;
    return true;
}

// Rebuilds the structured UI snapshot lazily for browser-side DOM renderers.
fn refreshTreeBuffer() bool {
    const p = getProgram() orelse return false;
    tree_buffer.clearRetainingCapacity();
    const writer = tree_buffer.writer(allocator);
    tea.ui.renderModelJson(App, allocator, &p.model, writer) catch return false;
    return true;
}

// Refreshes both flat text and structured tree buffers after direct model
// mutations initiated by browser-only helpers.
fn refreshBuffers() bool {
    return refreshRenderBuffer() and refreshTreeBuffer();
}

// Normalizes browser-side numeric key codes into runtime keys.
fn decodeKey(code: u32) tea.Key {
    return switch (code) {
        3 => tea.Key.ctrl_c,
        26 => tea.Key.ctrl_z,
        1001 => tea.Key.up,
        1002 => tea.Key.down,
        1003 => tea.Key.left,
        1004 => tea.Key.right,
        1005 => tea.Key.home,
        1006 => tea.Key.end,
        1007 => tea.Key.delete,
        1008 => tea.Key.page_up,
        1009 => tea.Key.page_down,
        1010 => tea.Key.shift_tab,
        9 => tea.Key.tab,
        13 => tea.Key.enter,
        27 => tea.Key.escape,
        127 => tea.Key.backspace,
        else => if (code >= 32 and code < 0x110000)
            tea.Key.character(@intCast(code))
        else
            tea.Key.unknown(@min(code, 255)),
    };
}

// Maps browser-level button identifiers back to runtime mouse buttons.
fn decodeMouseButton(code: u8) ?tea.MouseButton {
    return switch (code) {
        0 => .none,
        1 => .left,
        2 => .middle,
        3 => .right,
        4 => .wheel_up,
        5 => .wheel_down,
        6 => .wheel_left,
        7 => .wheel_right,
        else => null,
    };
}

// Maps browser-level action identifiers back to runtime mouse actions.
fn decodeMouseAction(code: u8) ?tea.MouseAction {
    return switch (code) {
        1 => .press,
        2 => .release,
        3 => .drag,
        4 => .move,
        5 => .scroll,
        else => null,
    };
}

// Maps browser-facing showcase region ids back to known app panels.
fn decodeRegion(code: u8) ?showcase.BrowserRegion {
    return switch (code) {
        @intFromEnum(showcase.BrowserRegion.filter) => .filter,
        @intFromEnum(showcase.BrowserRegion.list) => .list,
        @intFromEnum(showcase.BrowserRegion.menu) => .menu,
        @intFromEnum(showcase.BrowserRegion.form) => .form,
        else => null,
    };
}

// Maps browser-facing showcase action ids back to interactive item handlers.
fn decodeAction(code: u8) ?showcase.BrowserAction {
    return switch (code) {
        @intFromEnum(showcase.BrowserAction.list_item) => .list_item,
        @intFromEnum(showcase.BrowserAction.menu_item) => .menu_item,
        @intFromEnum(showcase.BrowserAction.form_field) => .form_field,
        else => null,
    };
}

// Validates a UTF-8 payload before it is forwarded as a paste event.
fn isValidUtf8(text: []const u8) bool {
    var index: usize = 0;
    while (index < text.len) {
        const sequence_len = std.unicode.utf8ByteSequenceLength(text[index]) catch return false;
        if (index + sequence_len > text.len) return false;
        _ = std.unicode.utf8Decode(text[index .. index + sequence_len]) catch return false;
        index += sequence_len;
    }
    return true;
}
