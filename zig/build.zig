const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("bubbletea_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const showcase = b.addExecutable(.{
        .name = "bubbletea-zig-showcase",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/showcase/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "bubbletea_zig", .module = mod },
            },
        }),
    });
    b.installArtifact(showcase);

    const run_cmd = b.addRunArtifact(showcase);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the Zig Bubble Tea showcase");
    run_step.dependOn(&run_cmd.step);

    const wasm = b.addExecutable(.{
        .name = "bubbletea-zig-showcase-wasm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm_showcase.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .freestanding,
            }),
            .optimize = optimize,
            .imports = &.{
                .{ .name = "bubbletea_zig", .module = mod },
            },
        }),
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.export_memory = true;

    const install_wasm = b.addInstallArtifact(wasm, .{});
    const wasm_step = b.step("wasm", "Build the WASM showcase module");
    wasm_step.dependOn(&install_wasm.step);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run Zig module tests");
    test_step.dependOn(&run_mod_tests.step);
}
