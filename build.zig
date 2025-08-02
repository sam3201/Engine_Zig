const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "Engine",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add conditional compilation based on target
    if (target.result.cpu.arch == .wasm32) {
        // For WASM builds, include WASM exports
        exe.root_module.addAnonymousImport("wasm_exports", .{
            .root_source_file = b.path("src/wasm_exports.zig"),
        });
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const wasm_target_query = std.Target.Query{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    };

    const wasm_exe = b.addExecutable(.{
        .name = "Engine",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(wasm_target_query),
        .optimize = optimize,
    });

    const wasm_step = b.step("wasm", "Build for WASM");
    wasm_step.dependOn(&b.addInstallArtifact(wasm_exe, .{}).step);
}
