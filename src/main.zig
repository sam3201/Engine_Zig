// src/main.zig
const std = @import("std");
const Engine = @import("Engine.zig");
const Server = @import("Server.zig");
const Client = @import("Client.zig");
const Player = @import("Player.zig");
const Chunk = @import("Chunk.zig");
const Menu = @import("Menu.zig").Menu;
const WorldManager = @import("WorldManager.zig");

pub fn mainMenu(engine: *Engine.Engine) !u8 {
    const items = [_][]const u8{
        "Singleplayer",
        "Host Game",
        "Join Game",
        "View KeyBindings",
        "Quit",
    };

    var menu = Menu.init("Menu", &items, 'w', 's', '\n'); 

    while (true) {
        engine.canvas.clear(' ', .{ .r = 0, .g = 0, .b = 0 });
        menu.draw(&engine.canvas);
        try engine.canvas.flushToTerminal();

        if (try Engine.readKey()) |key| {
            if (key == 27) return 255; 
            if (menu.update(key)) |selected| {
                return @intCast(selected);
            }
        }
    }
}
 
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Clear screen and prompt user
    _ = std.posix.write(std.posix.STDOUT_FILENO, "\x1b[2J\x1b[H") catch {};
    std.debug.print("ASCII Engine Multiplayer Demo\n", .{});
    std.debug.print("1. Host Game (Server)\n", .{});
    std.debug.print("2. Join Game (Client)\n", .{});
    std.debug.print("Choose option: ", .{});

    var buf: [1]u8 = undefined;
    const n = try std.posix.read(std.posix.STDIN_FILENO, &buf);
    if (n == 0) return;

    const choice = buf[0];
    switch (choice) {
        '1' => try runServerMode(allocator),
        '2' => try runClientMode(allocator),
        else => std.debug.print("Invalid choice.\n", .{}),
    }
}

fn runServerMode(allocator: std.mem.Allocator) !void {
    std.debug.print("\nStarting server...\n", .{});

    // Initialize the game server
    var server = try Server.GameServer.init(allocator);
    defer server.deinit();

    // Run the server loop
    try server.startServer();
}

fn runClientMode(allocator: std.mem.Allocator) !void {
    std.debug.print("\nConnecting to host...\n", .{});

    // Create a new Engine for rendering the client
    var engine = try Engine.Engine.init(
        allocator,
        160, // width
        44,  // height
        30,  // FPS
        Engine.Color{ .r = 0, .g = 0, .b = 0 },
    );
    defer engine.deinit();

    // Connect and run the client loop
    try Client.runClient(allocator, &engine);
}

