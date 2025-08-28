// src/main.zig
const std = @import("std");
const Engine = @import("Engine.zig");
const Player = @import("Player.zig");
const WorldManager = @import("WorldManager.zig");
const Menu = @import("Menu.zig").Menu;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // ───────────── Title/Menu Engine ─────────────
    var engine = try Engine.Engine.init(
        allocator,
        80,
        24,
        30,
        Engine.Color{ .r = 10, .g = 10, .b = 10 },
    );
    defer engine.deinit();

    var term = try Engine.TerminalGuard.init();
    defer term.deinit();

    var menu = Menu.init(
        "Main Menu",
        &[_][]const u8{ "Start Game", "Options", "Quit" },
        'w', // up
        's', // down
        '\n', // select
    );

    var menu_choice: ?usize = null;
    while (engine.running and menu_choice == null) {
        engine.clock.tick();

        if (Engine.readKey() catch null) |key| { // non-blocking input
            if (menu.update(key)) |choice| {
                menu_choice = choice;
            }
        }

        engine.canvas.clear(' ', Engine.Color{ .r = 10, .g = 10, .b = 10 });
        menu.draw(&engine.canvas);
        engine.canvas.render();
        engine.canvas.flushToTerminal();
        engine.clock.sleepUntilNextFrame();
    }

    if (menu_choice) |choice| {
        switch (choice) {
            0 => std.debug.print("Starting game...\n", .{}),
            1 => {
                std.debug.print("Options not implemented yet.\n", .{});
                return;
            },
            2 => return,
            else => {},
        }
    }

    // ───────────── Game Engine ─────────────
    var game_engine = try Engine.Engine.init(
        allocator,
        80,
        24,
        30,
        Engine.Color{ .r = 10, .g = 10, .b = 10 },
    );
    defer game_engine.deinit();

    var player = try Player.createWASDPlayer(allocator, 0, 0);
    defer player.deinit();

    var world = try WorldManager.WorldManager.init(allocator, &game_engine.canvas, player);
    defer world.deinit();

    while (game_engine.running and player.isAlive()) {
        game_engine.clock.tick();

        // Non-blocking input
        if (Engine.readKey() catch null) |key| {
            if (key == 'q' or key == 'Q') break;
            try world.processPlayerInput(key);
        }

        // Clear screen
        game_engine.canvas.clear(' ', Engine.Color{ .r = 10, .g = 10, .b = 10 });

        const pos = player.getPosition();
        // ───────────── HUD ─────────────
        const hud1 = std.fmt.allocPrint(
            allocator,
            "HP: {d}/{d} | Pos: ({d},{d})",
            .{ player.health, player.max_health, pos.x, pos.y },
        ) catch unreachable;
        defer allocator.free(hud1);
        for (hud1, 0..) |c, i| {
            const int32_i: i32 = @intCast(i);
            game_engine.canvas.put(int32_i, 0, c);
        }

        // const hud2 = std.fmt.allocPrint(
        //    allocator,
        //    "Biome: {any} | Difficulty: {d}",
        //    .{ world.current_biome, world.difficulty },
        // ) catch unreachable;
        //defer allocator.free(hud2);
        //for (hud2, 0..) |c, i| {
        //    game_engine.canvas.put(i, 1, c);
        //}

        // ───────────── Draw World ─────────────
        world.draw();

        // Render
        game_engine.canvas.render();
        game_engine.canvas.flushToTerminal();
        game_engine.clock.sleepUntilNextFrame();
    }

    std.debug.print("Exited game.\n", .{});
}
