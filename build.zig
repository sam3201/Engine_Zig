const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Engine executable
    const exe = b.addExecutable("Engine", b.path("src/main.zig"), .{
        .target = target,
        .optimize = optimize,
    });

    // Server executable
    const server = b.addExecutable("Server", b.path("src/Server.zig"), .{
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(server);

    // Client executable
    const client = b.addExecutable("Client", b.path("src/Client.zig"), .{
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(client);

    // Conditional WASM build
    if (target.result.cpu.arch == .wasm32) {
        exe.addModuleAnonymous("wasm_exports", b.path("src/wasm_exports.zig"), .{});
    }

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // WASM target build step
    const wasm_target_query = std.Target.Query{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    };

    const wasm_exe = b.addExecutable("Engine", b.path("src/main.zig"), .{
        .target = b.resolveTargetQuery(wasm_target_query),
        .optimize = optimize,
    });

    const wasm_step = b.step("wasm", "Build for WASM");
    wasm_step.dependOn(&b.addInstallArtifact(wasm_exe, .{}).step);
}

