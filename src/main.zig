// src/main.zig

const std = @import("std");
const Engine = @import("Engine.zig");
const Engine3D = @import("Engine3D.zig");
const Server = @import("Server.zig");
const Client = @import("Client.zig");
const Player = @import("Player.zig");
const Chunk = @import("Chunk.zig");
const WorldManager = @import("WorldManager.zig");
const Menu = @import("Menu.zig").Menu;
const Thread = std.Thread;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var engine = try Engine.Engine.init(
        allocator,
        100, 40, 30,
        Engine.Color{ .r = 0, .g = 0, .b = 0 },
    );
    defer engine.deinit();

    var terminal_guard = try Engine.TerminalGuard.init();
    defer terminal_guard.deinit();

    const selection = try mainMenu(&engine);

    switch (selection) {
        0 => try runSingleplayer(allocator, &engine),
        1 => try runHostMode(allocator, &engine),
        2 => try runClientMode(allocator, &engine),
        3 => try showKeyBindings(&engine),
        else => {
            std.debug.print("Goodbye!\n", .{});
            return;
        },
    }
}

// ==============================
// 🎮 Menu System
// ==============================

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
        engine.canvas.clear(' ', .{ .r = 0, .g = 0, .b = 0 });
        menu.draw(&engine.canvas);
        try engine.canvas.flushToTerminal();

        if (try Engine.readKey()) |key| {
            if (key == 'q' or key == 27) break;
            if (menu.update(key)) |sel| {
                selection = sel;
                break;
            }
        }

        engine.clock.sleepUntilNextFrame();
    }

    return @intCast(selection);
}

fn viewModeMenu(engine: *Engine.Engine) !u8 {
    const items = [_][]const u8{
        "2D View (Classic)",
        "3D View (Experimental)",
        "Back",
    };

    var menu = Menu.init("Choose View Mode", &items, 'w', 's', 'p');
    var selection: usize = 0;

    while (true) {
        engine.canvas.clear(' ', .{ .r = 0, .g = 0, .b = 0 });
        menu.draw(&engine.canvas);
        try engine.canvas.flushToTerminal();

        if (try Engine.readKey()) |key| {
            if (key == 'q' or key == 27) {
                selection = 2; // Back
                break;
            }
            if (menu.update(key)) |sel| {
                selection = sel;
                break;
            }
        }

        engine.clock.sleepUntilNextFrame();
    }

    return @intCast(selection);
}

// ==============================
// 🧙 Singleplayer
// ==============================

fn runSingleplayer(allocator: std.mem.Allocator, engine: *Engine.Engine) !void {
    const view_mode = try viewModeMenu(engine);
    
    switch (view_mode) {
        0 => try runSingleplayer2D(allocator, engine),
        1 => try runSingleplayer3D(allocator, engine),
        else => return, // Back to main menu
    }
}

fn runSingleplayer2D(allocator: std.mem.Allocator, engine: *Engine.Engine) !void {
    const player = try Player.Player.createWASDPlayer("Player", allocator, 5, 5);
    var world = try WorldManager.WorldManager.init(
        Chunk.ChunkCoord{ .x = 0, .y = 0 },
        1,
        allocator,
        &engine.canvas,
        player,
    );
    defer world.deinit();

    engine.running = true;

    while (engine.running) {
        engine.clock.tick();

        if (try Engine.readKey()) |key| {
            if (key == 'q' or key == 27) break;
            const action = Player.InputAction.fromKey(key);
            try world.handlePlayerAction(action);
        }

        engine.canvas.clear(' ', engine.background_color);
        world.draw();
        try engine.canvas.flushToTerminal();

        engine.clock.sleepUntilNextFrame();
    }
}

fn runSingleplayer3D(allocator: std.mem.Allocator, engine: *Engine.Engine) !void {
    var canvas3d = try Engine3D.Canvas3D.init(allocator, engine.canvas.width, engine.canvas.height);
    defer canvas3d.deinit();

    const player = try Player.Player.createWASDPlayer("Player", allocator, 5, 5);
    var world = try WorldManager.WorldManager.init(
        Chunk.ChunkCoord{ .x = 0, .y = 0 },
        1,
        allocator,
        &engine.canvas,
        player,
    );
    defer world.deinit();

    var cam3d = Engine3D.Camera3D.init(@intCast(canvas3d.width), @intCast(canvas3d.height));
    cam3d.z = 2;

    engine.running = true;

    // Show controls hint
    const hint_text = "3D View | WASD: Move | Q/ESC: Quit";
    for (hint_text, 0..) |ch, i| {
        engine.canvas.put(@intCast(i), 0, ch);
        engine.canvas.fillColor(@intCast(i), 0, .{ .r = 200, .g = 200, .b = 100 });
    }
    try engine.canvas.flushToTerminal();
    std.Thread.sleep(2 * std.time.ns_per_s); 

    while (engine.running) {
        engine.clock.tick();

        if (try Engine.readKey()) |key| {
            if (key == 'q' or key == 27) break;
            const action = Player.InputAction.fromKey(key);
            try world.handlePlayerAction(action);
        }

        // Update camera to follow player
        const pos = world.player.getPosition();
        cam3d.x = pos.x - @divTrunc(@as(i32, @intCast(canvas3d.width)), 2);
        cam3d.y = pos.y;

        // Project world to 3D
        world.projectTo3D(&canvas3d, &cam3d);

        // Draw player info overlay in top-left
        const player_info = try std.fmt.allocPrint(
            allocator,
            "HP: {}/{} | Pos: ({},{}) | 3D MODE",
            .{ world.player.health, world.player.max_health, pos.x, pos.y },
        );
        defer allocator.free(player_info);

        for (player_info, 0..) |ch, i| {
            if (i < canvas3d.width) {
                canvas3d.put(@intCast(i), 0, ch);
                canvas3d.fillColor(@intCast(i), 0, Engine3D.Color3D.init(255, 255, 100));
            }
        }

        try canvas3d.flushToTerminal();
        engine.clock.sleepUntilNextFrame();
    }
}

// ==============================
// 🌐 Host Mode
// ==============================

fn runHostMode(allocator: std.mem.Allocator, engine: *Engine.Engine) !void {
    std.debug.print("Hosting server and playing as host...\n", .{});

    var server = try Server.GameServer.init(allocator);
    const server_thread = try Thread.spawn(.{}, runServerThread, .{&server});
    server_thread.detach();

    // Host acts as local client
    try Client.runClient(allocator, engine);
}

fn runServerThread(server: *Server.GameServer) void {
    server.startServer() catch |err| {
        std.debug.print("Server error: {any}\n", .{err});
    };
}

// ==============================
// 💻 Client Mode
// ==============================

fn runClientMode(allocator: std.mem.Allocator, engine: *Engine.Engine) !void {
    std.debug.print("Joining game...\n", .{});
    try Client.runClient(allocator, engine);
}

// ==============================
// ⚙️ Key Bindings Display
// ==============================

fn showKeyBindings(engine: *Engine.Engine) !void {
    const text =
        "=== CONTROLS ===\n" ++
        "\n" ++
        "Movement:\n" ++
        "  WASD - Move Player\n" ++
        "\n" ++
        "Actions:\n" ++
        "  E - Interact/Pick up items\n" ++
        "  O - Drop item\n" ++
        "  U - Use item\n" ++
        "  I - Open inventory\n" ++
        "  SPACE - Attack\n" ++
        "\n" ++
        "Inventory:\n" ++
        "  0-9 - Select hotbar slot\n" ++
        "\n" ++
        "Menu:\n" ++
        "  P - Select menu option\n" ++
        "  Q or ESC - Quit/Back\n" ++
        "\n" ++
        "Press any key to return...";

    engine.canvas.clear(' ', .{ .r = 0, .g = 0, .b = 0 });
    var x: i32 = 5;
    var y: i32 = 3;

    for (text) |ch| {
        if (ch == '\n') {
            y += 1;
            x = 5;
            continue;
        }
        if (y < engine.canvas.height and x < engine.canvas.width) {
            engine.canvas.put(x, y, ch);
            engine.canvas.fillColor(x, y, .{ .r = 200, .g = 200, .b = 200 });
            x += 1;
        }
    }

    try engine.canvas.flushToTerminal();
    
    // Wait for any key
    while (true) {
        if (try Engine.readKey()) |_| {
            break;
        }
        engine.clock.sleepUntilNextFrame();
    }
}
