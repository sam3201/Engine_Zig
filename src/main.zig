const std = @import("std");
const Engine = @import("Engine.zig");
const Player = @import("Player.zig");
const WorldManager = @import("WorldManager.zig");
const Menu = @import("Menu.zig").Menu;
const thread = std.Thread;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Engine for title/menu
    var engine = try Engine.Engine.init(
        allocator,
        80,
        24,
        30,
        Engine.Color{ .r = 10, .g = 10, .b = 10 },
    );
    defer engine.deinit();

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

        if (try Engine.readKey()) |key| {
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

    // ───────────── Game Init ─────────────
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

        if (try Engine.readKey()) |key| {
            if (key == 'q' or key == 'Q') break;
            try world.processPlayerInput(key);
        }

        game_engine.canvas.clear(' ', Engine.Color{ .r = 10, .g = 10, .b = 10 });
        world.draw();
        game_engine.canvas.render();
        game_engine.canvas.flushToTerminal();
        game_engine.clock.sleepUntilNextFrame();
    }
}
