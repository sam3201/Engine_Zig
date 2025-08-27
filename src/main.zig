const std = @import("std");
const Engine = @import("Engine.zig");
const Player = @import("Player.zig");
const WorldManager = @import("WorldManager.zig");
const Menu = @import("Menu.zig");
const Thread = std.Thread;

fn drawTitleScreen(canvas: *Engine.Canvas) void {
    const white = Engine.Color{ .r = 255, .g = 255, .b = 255 };
    const green = Engine.Color{ .r = 0, .g = 255, .b = 0 };

    const title = "Infinite World Adventure";
    const title_start = (80 - title.len) / 2;
    for (title, 0..) |char, i| {
        canvas.put(@intCast(title_start + i), 5, char);
        canvas.fillColor(@intCast(title_start + i), 5, green);
    }

    const subtitle = "A Multiplayer Open World Game";
    const subtitle_start = (80 - subtitle.len) / 2;
    for (subtitle, 0..) |char, i| {
        canvas.put(@intCast(subtitle_start + i), 7, char);
        canvas.fillColor(@intCast(subtitle_start + i), 7, white);
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // ───────────── Title Menu ─────────────
    var menu = Menu.init(
        "Main Menu",
        &[_][]const u8{ "Start", "Options", "Quit" },
        'w',   // up
        's',   // down
        '\n',  // confirm (Enter)
    );

    var menu_running = true;
    var menu_choice: ?usize = null;

    while (menu_running) {
        // Clear terminal each frame
        std.debug.print("\x1B[2J\x1B[H", .{}); // ANSI clear screen
        drawTitleScreen(undefined); // optionally skip Engine here
        menu.draw();

        if (try Engine.readKey()) |key| {
            if (menu.update(key)) |choice| {
                menu_choice = choice;
                menu_running = false;
            }
        }
    }

    if (menu_choice) |choice| {
        switch (choice) {
            0 => std.debug.print("Starting game...\n", .{}),
            1 => {
                std.debug.print("Options not implemented yet.\n", .{});
                return;
            },
            2 => {
                std.debug.print("Quit selected. Exiting...\n", .{});
                return;
            },
            else => {},
        }
    }

    // ───────────── Game Init ─────────────
    var engine = try Engine.Engine.init(
        allocator,
        80,
        24,
        30,
        Engine.Color{ .r = 10, .g = 10, .b = 10 },
    );
    defer engine.deinit();

    var player = try Player.createWASDPlayer(allocator, 0, 0);
    defer player.deinit();

    var world = try WorldManager.WorldManager.init(allocator, &engine.canvas, player);
    defer world.deinit();

    while (engine.running and player.isAlive()) {
        engine.clock.tick();

        // Input
        if (try Engine.readKey()) |key| {
            if (key == 'q' or key == 'Q') break;
            try world.processPlayerInput(key);
        }

        // Draw
        engine.canvas.clear(' ', Engine.Color{ .r = 10, .g = 10, .b = 10 });
        world.draw();
        engine.canvas.render();
        engine.canvas.flushToTerminal();
        engine.clock.sleepUntilNextFrame();
    }

    std.debug.print("Exited single-player world.\n", .{});
}

