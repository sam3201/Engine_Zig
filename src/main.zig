// src/main.zig

const std = @import("std");
const Engine = @import("Engine.zig");
const Player = @import("Player.zig");
const WorldManager = @import("WorldManager.zig");
const Server = @import("Server.zig");
const Thread = std.Thread;
const process = std.process;

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

    const instructions = [_][]const u8{
        "Press any key to start the server",
        "Host controls difficulty",
        "Clients connect to 127.0.0.1:42069",
        // TODO: Add save/load game instructions in future
    };

    var y_offset: i32 = 12;
    for (instructions) |instruction| {
        const start_x = (80 - instruction.len) / 2;
        for (instruction, 0..) |char, i| {
            canvas.put(@intCast(start_x + i), y_offset, char);
            canvas.fillColor(@intCast(start_x + i), y_offset, white);
        }
        y_offset += 2;
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Show title screen
    var title_engine = try Engine.Engine.init(allocator, 80, 24, 30, Engine.Color{ .r = 10, .g = 10, .b = 10 });
    defer title_engine.deinit();

    const UpdateFunctions = struct {
        fn update(canvas: *Engine.Canvas) void {
            canvas.clear(' ', Engine.Color{ .r = 10, .g = 10, .b = 10 });
            drawTitleScreen(canvas);
        }
    };

    title_engine.canvas.setUpdateFn(&UpdateFunctions.update);

    var term = try Engine.TerminalGuard.init();
    defer term.deinit();

    while (title_engine.running) {
        title_engine.clock.tick();

        if (try Engine.readKey() != null) {
            title_engine.running = false;
            break;
        }

        title_engine.canvas.clear(' ', Engine.Color{ .r = 10, .g = 10, .b = 10 });
        UpdateFunctions.update(&title_engine.canvas);
        title_engine.canvas.render();
        title_engine.canvas.flushToTerminal();
        title_engine.clock.sleepUntilNextFrame();
    }

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
