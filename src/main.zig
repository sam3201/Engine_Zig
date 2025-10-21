const std = @import("std");
const Engine = @import("Engine.zig");
const Server = @import("Server.zig");
const Client = @import("Client.zig");
const Player = @import("Player.zig");
const Chunk = @import("Chunk.zig");
const WorldManager = @import("WorldManager.zig");
const Menu = @import("Menu.zig").Menu;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var engine = try Engine.Engine.init(
        allocator,
        100,
        40,
        30,
        Engine.Color{ .r = 0, .g = 0, .b = 0 },
    );
    defer engine.deinit();

    var terminal_guard = try Engine.TerminalGuard.init();
    defer terminal_guard.deinit();

    const selection = try mainMenu(&engine);

    switch (selection) {
        0 => try runSingleplayer(allocator, &engine),
        1 => try runServerMode(allocator),
        2 => try runClientMode(allocator, &engine),
        3 => try showKeyBindings(&engine),
        else => std.debug.print("Goodbye!\n", .{}),
    }
}

fn mainMenu(engine: *Engine.Engine) !u8 {
    const items = [_][]const u8{
        "Single Player",
        "Host Game",
        "Join Game",
        "View Key Bindings",
        "Quit",
    };

    var menu = Menu.init("Main Menu", &items, 'w', 's', 'p');
    var selection: usize = 0;

    while (true) {
        _ = std.posix.write(std.posix.STDOUT_FILENO, "\x1b[2J\x1b[H") catch {};
        engine.clock.tick();

        if (try Engine.readKey()) |key| {
            if (key == 'q' or key == 27) break;
            if (menu.update(key)) |sel| {
                selection = sel;
                break;
            }
        }

        engine.canvas.clear(' ', .{ .r = 0, .g = 0, .b = 0 });
        menu.draw(&engine.canvas);
        try engine.canvas.flushToTerminal();
        engine.clock.sleepUntilNextFrame();
    }

    return @intCast(selection);
}

fn runSingleplayer(allocator: std.mem.Allocator, engine: *Engine.Engine) !void {
    var player = try Player.Player.createWASDPlayer("Hero", allocator, 10, 10);
    defer player.deinit();

    var world = try WorldManager.WorldManager.init(
        Chunk.ChunkCoord{ .x = 0, .y = 0 },
        1,
        allocator,
        &engine.canvas,
        player,
    );
    defer world.deinit();

    while (engine.running) {
        engine.clock.tick();

        if (try Engine.readKey()) |key| {
            if (key == 'q' or key == 27) break;
            const action = Player.InputAction.fromKey(key);
            try world.handlePlayerAction(action);
        }

        engine.canvas.clear(' ', .{ .r = 0, .g = 0, .b = 0 });
        try world.draw();
        try engine.canvas.flushToTerminal();
        engine.clock.sleepUntilNextFrame();
    }
}

fn runServerMode(allocator: std.mem.Allocator) !void {
    std.debug.print("Starting game server...\n", .{});
    var server = try Server.GameServer.init(allocator);
    defer server.deinit();
    try server.startServer();
}

fn runClientMode(allocator: std.mem.Allocator, engine: *Engine.Engine) !void {
    std.debug.print("Connecting to host...\n", .{});
    try Client.runClient(allocator, engine);
}

fn showKeyBindings(engine: *Engine.Engine) !void {
    const text =
        "WASD - Move\n" ++
        "P - Select Menu Option\n" ++
        "Q / ESC - Quit\n";

    engine.canvas.clear(' ', .{ .r = 0, .g = 0, .b = 0 });
    var x: i32 = 5;
    var y: i32 = 5;
    for (text) |ch| {
        if (ch == '\n') {
            y += 1;
            x = 5;
            continue;
        }
        engine.canvas.put(x, y, ch);
        engine.canvas.fillColor(x, y, .{ .r = 255, .g = 255, .b = 255 });
        x += 1;
    }
    try engine.canvas.flushToTerminal();
    _ = try Engine.readKey();
}

