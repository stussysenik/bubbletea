const std = @import("std");
const tea = @import("bubbletea_zig");
const showcase = tea.apps.showcase;

const Msg = tea.Message(void);
const App = showcase.App(Msg);

/// Boots the native terminal showcase against the shared runtime module.
pub fn main() !void {
    // The showcase currently owns its own allocations, so a general-purpose
    // allocator keeps the entrypoint simple while still catching leaks in dev.
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();

    const gpa = gpa_state.allocator();

    // Run the shared app through the interactive terminal host.
    var program = tea.Program(App, void).init(gpa, .{}, .{});
    defer program.deinit();

    _ = try program.run();
}
