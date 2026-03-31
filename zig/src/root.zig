const tea = @import("tea.zig");

pub const input = @import("input.zig");
pub const ui = @import("ui.zig");
pub const renderer = @import("renderer.zig");
pub const terminal = @import("terminal.zig");
pub const HeadlessProgram = @import("headless.zig").HeadlessProgram;
pub const Key = tea.Key;
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

pub const components = struct {
    pub const Badge = @import("components/badge.zig").Badge;
    pub const Spinner = @import("components/spinner.zig").Spinner;
    pub const List = @import("components/list.zig").List;
    pub const ProgressBar = @import("components/progress.zig").ProgressBar;
};

pub const apps = struct {
    pub const showcase = @import("apps/showcase.zig");
};

test {
    _ = @import("input.zig");
    _ = @import("tea.zig");
    _ = @import("ui.zig");
    _ = @import("headless.zig");
    _ = @import("components/badge.zig");
    _ = @import("components/spinner.zig");
    _ = @import("components/list.zig");
    _ = @import("components/progress.zig");
    _ = @import("apps/showcase.zig");
}
