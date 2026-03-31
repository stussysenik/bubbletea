const tea = @import("tea.zig");

/// Public package surface for the Zig rewrite.
pub const input = @import("input.zig");
pub const focus = @import("focus.zig");
pub const ui = @import("ui.zig");
pub const renderer = @import("renderer.zig");
pub const terminal = @import("terminal.zig");
/// Deterministic, host-agnostic runtime used by tests and WASM.
pub const HeadlessProgram = @import("headless.zig").HeadlessProgram;
/// Stateful terminal decoder that can drain multiple keys from one read.
pub const InputDecoder = input.Decoder;
/// Higher-level terminal event emitted by the decoder.
pub const InputEvent = input.Event;
/// Shared focus helper for components and applications.
pub const FocusRing = focus.FocusRing;
pub const Key = tea.Key;
pub const MouseAction = tea.MouseAction;
pub const MouseButton = tea.MouseButton;
pub const MouseModifiers = tea.MouseModifiers;
pub const MouseEvent = tea.MouseEvent;
pub const MouseMode = tea.MouseMode;
pub const Size = tea.Size;
pub const Renderer = tea.Renderer;
pub const Terminal = tea.Terminal;
pub const TimerMsg = tea.TimerMsg;
pub const Message = tea.Message;
pub const Cmd = tea.Cmd;
pub const Update = tea.Update;
pub const emit = tea.emit;
pub const tickAfter = tea.tickAfter;
pub const Program = tea.Program;

/// Reusable UI widgets built on top of the shared view tree.
pub const components = struct {
    pub const Badge = @import("components/badge.zig").Badge;
    pub const Spinner = @import("components/spinner.zig").Spinner;
    pub const List = @import("components/list.zig").List;
    pub const ProgressBar = @import("components/progress.zig").ProgressBar;
    pub const TextInput = @import("components/text_input.zig").TextInput;
    pub const Table = @import("components/table.zig").Table;
    pub const Form = @import("components/form.zig").Form;
};

/// Example applications that exercise the runtime and components together.
pub const apps = struct {
    pub const showcase = @import("apps/showcase.zig");
};

test {
    _ = @import("input.zig");
    _ = @import("focus.zig");
    _ = @import("tea.zig");
    _ = @import("ui.zig");
    _ = @import("headless.zig");
    _ = @import("components/badge.zig");
    _ = @import("components/spinner.zig");
    _ = @import("components/list.zig");
    _ = @import("components/progress.zig");
    _ = @import("components/text_input.zig");
    _ = @import("components/table.zig");
    _ = @import("components/form.zig");
    _ = @import("apps/showcase.zig");
}
