const std = @import("std");

/// Wires the reusable library module, the native showcase binary, the
/// freestanding WASM showcase, the browser host assets, and the standard
/// test/run steps.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Export the rewrite as a normal Zig module so examples and downstream
    // apps can import the same runtime and components.
    const mod = b.addModule("bubbletea_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // Native terminal showcase used during day-to-day development.
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

    // Browser hosts can load this freestanding module and drive the same app
    // state through a thin JS bridge.
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

    // The web step installs both the browser shell and a colocated WASM
    // module so the host can be served as static files without extra
    // post-processing.
    const install_web_assets = b.addInstallDirectory(.{
        .source_dir = b.path("web"),
        .install_dir = .prefix,
        .install_subdir = "web/showcase",
    });
    const install_web_wasm = b.addInstallArtifact(wasm, .{
        .dest_dir = .{
            .override = .{ .custom = "web/showcase" },
        },
        .dest_sub_path = "bubbletea-zig-showcase.wasm",
    });
    const web_step = b.step("web", "Build the browser showcase host");
    web_step.dependOn(&install_web_assets.step);
    web_step.dependOn(&install_web_wasm.step);

    // Module tests cover the runtime, rendering, and component layers.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run Zig module tests");
    test_step.dependOn(&run_mod_tests.step);

    // Package docs are part of the supported surface, so keep them buildable
    // alongside the rest of the module.
    const docs_lib = b.addLibrary(.{
        .name = "bubbletea-zig-docs",
        .linkage = .static,
        .root_module = mod,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Build package docs");
    docs_step.dependOn(&install_docs.step);
}
