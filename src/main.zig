const std = @import("std");
const Engine = @import("Engine.zig");
const Player = @import("Player.zig");
const WorldManager = @import("WorldManager.zig");
const TitleScreen = @import("TitleScreen.zig");
const Server = @import("Server.zig");
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const process = std.process;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Show title screen
    var title_engine = try Engine.Engine.init(allocator, 80, 24, 30, Engine.Color{ .r = 10, .g = 10, .b = 10 });
    defer title_engine.deinit();

    var title_screen = try TitleScreen.init(allocator, &title_engine.canvas);
    defer title_screen.deinit();

    try title_screen.run(&title_engine);

    // Start server after title screen
    std.debug.print("Starting Open World Game Server\n", .{});
    std.debug.print("Available CPU cores: {d}\n", .{Thread.getCpuCount() catch 1});

    var server = try Server.GameServer.init(allocator);
    defer server.deinit();

    // Start server
    try server.startServer();

    std.debug.print("Open World Game Server terminated\n", .{});
}

pub fn setInput(input: u8) void {
    _ = input;
}
