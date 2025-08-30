const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create modules for each executable
    const engine_mod = b.addModule("engine_mod", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
    });

    const server_mod = b.addModule("server_mod", .{
        .root_source_file = b.path("src/Server.zig"),
        .target = target,
    });

    const client_mod = b.addModule("client_mod", .{
        .root_source_file = b.path("src/Client.zig"),
        .target = target,
    });

    // Create executables
    const exe_engine = b.addExecutable(.{
        .name = "Engine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "engine_mod", .module = engine_mod },
            },
        }),
    });
    b.installArtifact(exe_engine);

    const exe_server = b.addExecutable(.{
        .name = "Server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/Server.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "server_mod", .module = server_mod },
            },
        }),
    });
    b.installArtifact(exe_server);

    const exe_client = b.addExecutable(.{
        .name = "Client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/Client.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "client_mod", .module = client_mod },
            },
        }),
    });
    b.installArtifact(exe_client);

    // Run step for Engine
    const run_cmd = b.addRunArtifact(exe_engine);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the Engine");
    run_step.dependOn(&run_cmd.step);
}
