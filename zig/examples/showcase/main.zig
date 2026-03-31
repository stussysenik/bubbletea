const std = @import("std");
const tea = @import("bubbletea_zig");
const showcase = tea.apps.showcase;

const Msg = tea.Message(void);
const App = showcase.App(Msg);

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();

    const gpa = gpa_state.allocator();

    var program = tea.Program(App, void).init(gpa, .{}, .{});
    defer program.deinit();

    _ = try program.run();
}
