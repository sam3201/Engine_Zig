// src/main.zig
const std = @import("std");
const Engine = @import("Engine.zig");
const Player = @import("Player.zig");
const WorldManager = @import("WorldManager.zig");
const Chunk = @import("Chunk.zig");
const Menu = @import("Menu.zig").Menu;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const WIDTH = 100;
    const HEIGHT = 30;
    const FPS = 60; 

    var engine = try Engine.Engine.init(
        allocator,
        WIDTH,
        HEIGHT,
        FPS,
        Engine.Color{ .r = 10, .g = 10, .b = 10 },
    );
    defer engine.deinit();

    var term = try Engine.TerminalGuard.init();
    defer term.deinit();

    // ───────────── Title Menu ─────────────
    var title_menu = Menu.init(
        "Main Menu",
        &[_][]const u8{ "Start Game", "Options", "Quit" },
        'w', // up
        's', // down
        '\n', // select
    );

    var title_menu_choice: ?usize = null;
    while (engine.running and title_menu_choice == null) {
        engine.clock.tick();

        if (Engine.readKey() catch null) |key| {
            if (title_menu.update(key)) |choice| {
                title_menu_choice = choice;
            }
        }

        engine.canvas.clear(' ', Engine.Color{ .r = 10, .g = 10, .b = 10 });
        title_menu.draw(&engine.canvas);
        engine.canvas.render();
        try engine.canvas.flushToTerminal();
        engine.clock.sleepUntilNextFrame();
    }

    if (title_menu_choice) |choice| {
        switch (choice) {
            0 => std.debug.print("Starting game...\n", .{}),
            1 => try optionsMenu(&engine),
            2 => return,
            else => {},
        }
    }

    // ───────────── Game Start ─────────────
    var game_engine = try Engine.Engine.init(
        allocator,
        WIDTH,
        HEIGHT,
        FPS,
        Engine.Color{ .r = 10, .g = 10, .b = 10 },
    );
    defer game_engine.deinit();

    var player = try Player.Player.createWASDPlayer("Player", allocator, 0, 0);
    defer player.deinit();

    var world = try WorldManager.WorldManager.init(Chunk.ChunkCoord{ .x = 0, .y = 0 }, 0, allocator, &game_engine.canvas, player);
    defer world.deinit();

    while (game_engine.running) {
        game_engine.clock.tick();

        if (Engine.readKey() catch null) |key| {
            if (key == 'q' or key == 'Q') break;
            try world.processPlayerInput(key);

            // Open in-game menu (not pausing server, just overlay)
            if (key == 'm' or key == 'M') {
                try ingameMenu(allocator, &game_engine, &player);
            }
        }

        game_engine.canvas.clear(' ', Engine.Color{ .r = 10, .g = 10, .b = 10 });

        const pos = player.getPosition();
        const hud1 = std.fmt.allocPrint(
            allocator,
            "HP: {d}/{d} | Pos: ({d},{d}) | Name: {s}",
            .{ player.health, player.max_health, pos.x, pos.y, player.name },
        ) catch unreachable;
        defer allocator.free(hud1);

        for (hud1, 0..) |c, i| {
            game_engine.canvas.put(@intCast(i), 0, c);
        }

        world.draw();

        game_engine.canvas.render();
        try game_engine.canvas.flushToTerminal();
        game_engine.clock.sleepUntilNextFrame();
    }

    std.debug.print("Exited game.\n", .{});
}

// ───────────── Options Menu (from Title) ─────────────
fn optionsMenu(engine: *Engine.Engine) !void {
    var options = Menu.init(
        "Options",
        &[_][]const u8{ "Change Name", "View Key Bindings", "Back" },
        'w',
        's',
        '\n',
    );

    var choice: ?usize = null;
    while (engine.running and choice == null) {
        engine.clock.tick();

        if (Engine.readKey() catch null) |key| {
            if (options.update(key)) |c| {
                choice = c;
            }
        }

        engine.canvas.clear(' ', Engine.Color{ .r = 10, .g = 10, .b = 10 });
        options.draw(&engine.canvas);
        engine.canvas.render();
        try engine.canvas.flushToTerminal();
        engine.clock.sleepUntilNextFrame();
    }

    if (choice) |c| {
        switch (c) {
            0 => std.debug.print("Name change not implemented yet (title).\n", .{}),
            1 => std.debug.print("Bindings: W/A/S/D = Move, E = Interact, I = Inventory, Space = Attack, M = Menu\n", .{}),
            else => {},
        }
    }
}

// ───────────── In-Game Menu ─────────────
fn ingameMenu(allocator: std.mem.Allocator, engine: *Engine.Engine, player: *Player.Player) !void {
    var menu = Menu.init(
        "In-Game Menu",
        &[_][]const u8{ "Change Name", "View Key Bindings", "Back" },
        'w',
        's',
        '\n',
    );

    var choice: ?usize = null;
    while (engine.running and choice == null) {
        engine.clock.tick();

        if (Engine.readKey() catch null) |key| {
            if (menu.update(key)) |c| {
                choice = c;
            }
        }

        engine.canvas.clear(' ', Engine.Color{ .r = 10, .g = 10, .b = 10 });
        menu.draw(&engine.canvas);
        engine.canvas.render();
        try engine.canvas.flushToTerminal();
        engine.clock.sleepUntilNextFrame();
    }

    if (choice) |c| {
        switch (c) {
            0 => {
                std.debug.print("Enter new name: ", .{});
                var buf_arr: [1024]u8 = undefined;
                var stdin_reader = std.fs.File.stdin().reader(&buf_arr);
                const bytes_read = try stdin_reader.readStreaming(buf_arr[0..]);
                if (bytes_read == 0) return;
                const name = buf_arr[0..bytes_read];
                player.*.name = try allocator.dupe(u8, name);
                try player.save("player.json");
            },

            1 => {
                std.debug.print("Bindings: W/A/S/D = Move, E = Interact, I = Inventory, Space = Attack, M = Menu\n", .{});
            },
            else => {},
        }
    }
}
