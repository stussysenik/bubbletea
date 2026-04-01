/// Shared lifecycle stages used by the documented runtime contract.
pub const LifecycleStage = enum {
    created,
    booted,
    running,
    quit,
    deinitialized,
};

/// Supported host categories for the Zig rewrite.
pub const HostKind = enum {
    terminal,
    headless,
    wasm,
};

/// Capabilities a host may provide around the shared update/render model.
pub const HostCapabilities = struct {
    input: bool,
    resize: bool,
    focus: bool,
    paste: bool,
    mouse: bool,
    clipboard_write: bool,
    clipboard_read: bool,
    timers: bool,
    frame_output: bool,
    structured_tree: bool,
    layout_hit_testing: bool,
    direct_targeting: bool,
};

/// One documented host profile for package docs and runtime planning.
pub const HostProfile = struct {
    kind: HostKind,
    name: []const u8,
    capabilities: HostCapabilities,
};

/// Interactive terminal host used by `tea.Program`.
pub const terminal = HostProfile{
    .kind = .terminal,
    .name = "terminal",
    .capabilities = .{
        .input = true,
        .resize = true,
        .focus = true,
        .paste = true,
        .mouse = true,
        .clipboard_write = true,
        .clipboard_read = true,
        .timers = true,
        .frame_output = true,
        .structured_tree = false,
        .layout_hit_testing = true,
        .direct_targeting = false,
    },
};

/// Deterministic host used by tests, automation, and browser bridges.
pub const headless = HostProfile{
    .kind = .headless,
    .name = "headless",
    .capabilities = .{
        .input = true,
        .resize = true,
        .focus = true,
        .paste = true,
        .mouse = true,
        .clipboard_write = true,
        .clipboard_read = true,
        .timers = true,
        .frame_output = true,
        .structured_tree = true,
        .layout_hit_testing = true,
        .direct_targeting = true,
    },
};

/// Browser-backed WASM host driven through exported C-compatible entrypoints.
pub const wasm = HostProfile{
    .kind = .wasm,
    .name = "wasm",
    .capabilities = .{
        .input = true,
        .resize = true,
        .focus = true,
        .paste = true,
        .mouse = true,
        .clipboard_write = true,
        .clipboard_read = true,
        .timers = true,
        .frame_output = true,
        .structured_tree = true,
        .layout_hit_testing = true,
        .direct_targeting = true,
    },
};
