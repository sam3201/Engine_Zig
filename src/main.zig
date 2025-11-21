const std = @import("std");
const Engine = @import("Engine.zig");
const Engine3D = @import("Engine3D.zig");
const Server = @import("Server.zig");
const Client = @import("Client.zig");
const Player = @import("Player.zig");
const Chunk = @import("Chunk.zig");
const WorldManager = @import("WorldManager.zig");
const Particle = @import("Particle.zig");
const Menu = @import("Menu.zig").Menu;
const Thread = std.Thread;

pub const WIDTH = 175;
pub const HEIGHT = 50;

fn runSingleplayer(allocator: std.mem.Allocator, engine: *Engine.Engine) !void {
    const view_mode = try viewModeMenu(engine);

    var player = try Player.Player.createWASDPlayer("Player", allocator, 5, 5);

    switch (view_mode) {
        0 => try runSingleplayer2D(allocator, engine, &player),
        1 => try runSingleplayer3D(allocator, engine, &player),
        else => return,
    }
}

fn runSingleplayer2D(
    allocator: std.mem.Allocator,
    engine: *Engine.Engine,
    player: *Player.Player,
) !void {
    var world_manager = try WorldManager.WorldManager.init(
        Chunk.ChunkCoord{ .x = 0, .y = 0 },
        1,
        allocator,
        &engine.canvas,
        player.*,
    );
    defer world_manager.deinit();

    engine.running = true;

    while (engine.running) {
        engine.clock.tick();

        if (try Engine.readKey()) |key| {
            if (key == 'q' or key == 27) break;
            try world_manager.processPlayerInput(key);
        }

        engine.canvas.clear(' ', engine.background_color);
        world_manager.draw();
        engine.canvas.render();
        try engine.canvas.flushToTerminal();

        engine.clock.sleepUntilNextFrame();
    }
}

fn runSingleplayer3D(
    allocator: std.mem.Allocator,
    engine: *Engine.Engine,
    player: *Player.Player,
) !void {
    std.debug.print("\nStarting 3D mode...\n", .{});

    var world_manager = try WorldManager.WorldManager.init(
        Chunk.ChunkCoord{ .x = 0, .y = 0 },
        0,
        allocator,
        &engine.canvas,
        player.*,
    );
    defer world_manager.deinit();

    const cam_w = engine.canvas.width;
    const cam_h = engine.canvas.height;

    var engine3d = try Engine3D.Engine3D.init(
        allocator,
        cam_w,
        cam_h,
        30.0,
        Engine3D.Color3D.init(135, 206, 235),
    );
    defer engine3d.deinit();

    const cam_w_i32: i32 = @intCast(engine.canvas.width);
    const cam_h_i32: i32 = @intCast(engine.canvas.height);

    var cam3d = Engine3D.Camera3D.init(cam_w_i32, cam_h_i32);
    {
        const pos = player.getPosition();
        cam3d.x = pos.x - @divTrunc(cam3d.width, 2);
        cam3d.y = pos.y - @divTrunc(cam3d.height, 2);
    }

    const particle_field: ?Particle.ParticleField =
        world_manager.generateParticleField(allocator, Particle.ParticleQuality.Medium, 12)
        catch null;

    if (particle_field) |*pf| {
        defer pf.deinit();
    }

    var view_3d = true;
    engine.running = true;

    while (engine.running) {
        engine.clock.tick();

        if (try Engine.readKey()) |b| {
            switch (b) {
                'v' => view_3d = !view_3d,
                'q', 27 => break,
                else => try world_manager.processPlayerInput(b),
            }
        }

        if (!view_3d) {
            engine.canvas.clear(' ', engine.background_color);
            world_manager.draw();
            engine.canvas.render();
            try engine.canvas.flushToTerminal();

        } else {
            engine3d.canvas.clear(' ', Engine3D.Color3D.init(135, 206, 235));
            world_manager.projectTo3D(&engine3d.canvas, &cam3d);

            // ✔ FIXED: no more |*pf|, use |pf|
            if (particle_field) |pf| {
                world_manager.renderParticleField3D(&engine3d.canvas, &cam3d, pf);
            }

            engine3d.canvas.render();
            try engine3d.canvas.flushToTerminal();
        }

        engine.clock.sleepUntilNextFrame();
    }
}

fn qualityMenu(engine: *Engine.Engine) !u8 {
    const items = [_][]const u8{
        "Low Quality (Fast)",
        "Medium Quality (Balanced)",
        "High Quality (Detailed)",
        "Ultra Quality (Slow)",
        "Back",
    };

    var menu = Menu.init("Graphics Quality", &items, 'w', 's', 'p');
    var selection: usize = 0;

    while (true) {
        engine.canvas.clear(' ', .{ .r = 0, .g = 0, .b = 0 });
        menu.draw(&engine.canvas);
        try engine.canvas.flushToTerminal();

        if (try Engine.readKey()) |key| {
            if (key == 'q' or key == 27) {
                selection = 4;
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var engine = try Engine.Engine.init(
        allocator,
        WIDTH,
        HEIGHT,
        60,
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
                selection = 2;
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

fn runHostMode(allocator: std.mem.Allocator, engine: *Engine.Engine) !void {
    std.debug.print("Hosting server and playing as host...\n", .{});

    var server = try Server.GameServer.init(allocator);
    const server_thread = try Thread.spawn(.{}, runServerThread, .{ &server });
    server_thread.detach();

    try Client.runClient(allocator, engine);
}

fn runServerThread(server: *Server.GameServer) void {
    server.startServer() catch |err| {
        std.debug.print("Server error: {any}\n", .{err});
    };
}

fn runClientMode(allocator: std.mem.Allocator, engine: *Engine.Engine) !void {
    std.debug.print("Joining game...\n", .{});
    try Client.runClient(allocator, engine);
}

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

    while (true) {
        if (try Engine.readKey()) |_| break;
        engine.clock.sleepUntilNextFrame();
    }
}

