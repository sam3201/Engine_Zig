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
        std.time.sleep(50 * std.time.ns_per_ms);
    }
}
 
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var engine = try Engine.Engine.init(
        allocator,
        166,
        44,
        30,
        Engine.Color{ .r = 0, .g = 0, .b = 0 },
    );
    defer engine.deinit();

    const selection = try mainMenu(&engine);

    switch (selection) {
        0 => try runSingleplayer(allocator, &engine),
        1 => try runServerMode(allocator),
        2 => try runClientMode(allocator, &engine),
        3 => try showKeyBindings(&engine),
        4, 255 => std.debug.print("Goodbye!\n", .{}),
        else => std.debug.print("Invalid option.\n", .{}),
    }
}

fn runSingleplayer(allocator: std.mem.Allocator, engine: *Engine.Engine) !void {
    std.debug.print("Starting singleplayer game...\n", .{});
    // Later: start world generation or load game state
    _ = allocator;
    _ = engine;
}

fn runServerMode(allocator: std.mem.Allocator) !void {
    std.debug.print("\nHosting server...\n", .{});
    var server = try Server.GameServer.init(allocator);
    defer server.deinit();
    try server.startServer();
}

fn runClientMode(allocator: std.mem.Allocator, engine: *Engine.Engine) !void {
    std.debug.print("\nJoining host...\n", .{});
    try Client.runClient(allocator, engine);
}

fn showKeyBindings(engine: *Engine.Engine) !void {
    const text =
        "WASD - Move\n" ++
        "E - Interact\n" ++
        "I - Inventory\n" ++
        "Q or ESC - Quit\n";

    engine.canvas.clear(' ', .{ .r = 0, .g = 0, .b = 0 });

    var y: i32 = 5;
    for (text) |ch| {
        if (ch == '\n') {
            y += 1;
            continue;
        }
        engine.canvas.put(10, y, ch);
        engine.canvas.fillColor(10, y, .{ .r = 255, .g = 255, .b = 255 });
    }

    try engine.canvas.flushToTerminal();
    _ = try Engine.readKey();
}

