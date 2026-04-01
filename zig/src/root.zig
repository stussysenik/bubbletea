//! Public package surface for the Bubble Tea Zig rewrite.
//!
//! Stability:
//! - Recommended app-kit surface: `Program`, `HeadlessProgram`, `Message`,
//!   `Cmd`, `Update`, `emit`, `tickAfter`, `FocusRing`, `ui`, `components`,
//!   and `contract`.
//! - Advanced host/runtime surface: `input`, `InputDecoder`, `InputEvent`,
//!   `renderer`, and `terminal`.
//! - Example-only surface: `apps.showcase`.

const std = @import("std");
const tea = @import("tea.zig");

/// Shared lifecycle and host capability contracts.
pub const contract = @import("contract.zig");
/// Low-level input protocol helpers for custom hosts.
pub const input = @import("input.zig");
/// Focus routing helpers shared across components and applications.
pub const focus = @import("focus.zig");
/// Shared cell-width logic for layout-sensitive callers.
pub const cell_width = @import("cell_width.zig");
/// Composable view tree and structured snapshot utilities.
pub const ui = @import("ui.zig");
/// Advanced terminal renderer module for custom host adapters.
pub const renderer = @import("renderer.zig");
/// Advanced terminal host module for custom host adapters.
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
    pub const Inspector = @import("components/inspector.zig").Inspector;
    pub const Menu = @import("components/menu.zig").Menu;
    pub const Spinner = @import("components/spinner.zig").Spinner;
    pub const List = @import("components/list.zig").List;
    pub const ProgressBar = @import("components/progress.zig").ProgressBar;
    pub const TextInput = @import("components/text_input.zig").TextInput;
    pub const Table = @import("components/table.zig").Table;
    pub const Form = @import("components/form.zig").Form;
};

/// Example applications that exercise the runtime and components together.
/// These examples are intentionally unstable and should not be treated as the
/// package's long-term framework API.
pub const apps = struct {
    pub const showcase = @import("apps/showcase.zig");
};

test "root surface supports a minimal app-kit model" {
    const Msg = Message(void);
    const DemoInput = components.TextInput(32);
    const DemoForm = components.Form(1, 32);

    const Model = struct {
        input: DemoInput = DemoInput.init(.{
            .prompt = "demo> ",
            .placeholder = "type here",
        }),

        pub fn update(self: *@This(), msg: Msg) !Update(Msg) {
            return switch (msg) {
                .key => |key| if (self.input.update(key)) .{} else Update(Msg).noop(),
                else => Update(Msg).noop(),
            };
        }

        pub fn compose(self: *const @This(), tree: *ui.Tree) !ui.NodeId {
            return tree.box(
                try self.input.compose(tree),
                .{
                    .title = "Demo",
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = .accent,
                },
            );
        }
    };

    var program = HeadlessProgram(Model, void).init(std.testing.allocator, .{});
    defer program.deinit();

    var form = DemoForm.init(.{
        .{ .id = "name", .label = "Name" },
    }, .{});
    var tree = ui.Tree.init(std.testing.allocator);
    defer tree.deinit();
    _ = try form.compose(&tree);
    _ = contract.terminal;
    _ = FocusRing.init(1);
    try std.testing.expect(!(try program.drain()));
    const snapshot = try program.snapshot(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
}

test "root surface can build a custom component from ui primitives" {
    const Pill = struct {
        label: []const u8,
        tone: ui.Tone = .accent,

        fn compose(self: *const @This(), tree: *ui.Tree) !ui.NodeId {
            return tree.box(
                try tree.textStyled(self.label, .{ .tone = self.tone }),
                .{
                    .border = .none,
                    .padding = ui.Insets.symmetric(0, 1),
                    .tone = self.tone,
                },
            );
        }
    };

    var tree = ui.Tree.init(std.testing.allocator);
    defer tree.deinit();

    const pill = Pill{ .label = "custom" };
    const root = try pill.compose(&tree);

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);

    try tree.render(buffer.writer(std.testing.allocator), root, .{
        .ansi = false,
        .debug_cursor = true,
    });
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "custom") != null);
}

test {
    _ = @import("contract.zig");
    _ = @import("input.zig");
    _ = @import("focus.zig");
    _ = @import("cell_width.zig");
    _ = @import("tea.zig");
    _ = @import("ui.zig");
    _ = @import("headless.zig");
    _ = @import("components/badge.zig");
    _ = @import("components/inspector.zig");
    _ = @import("components/menu.zig");
    _ = @import("components/spinner.zig");
    _ = @import("components/list.zig");
    _ = @import("components/progress.zig");
    _ = @import("components/text_input.zig");
    _ = @import("components/table.zig");
    _ = @import("components/form.zig");
    _ = @import("apps/showcase.zig");
}
