const std = @import("std");
const Engine = @import("Engine.zig");
const Player = @import("Player.zig");
const WorldManager = @import("WorldManager.zig");
const Chunk = @import("Chunk.zig");
const Menu = @import("Menu.zig").Menu;

fn startHostServer(allocator: std.mem.Allocator) void {
    const Server = @import("Server.zig");
    var server = Server.GameServer.init(allocator) catch |err| {
        std.debug.print("Failed to start server: {any}\n", .{err});
        return;
    };
    defer server.deinit();
    server.startServer() catch |err| {
        std.debug.print("Server error: {any}\n", .{err});
    };
}

fn startClient(allocator: std.mem.Allocator) void {
    const Client = @import("Client.zig");

    var engine = Engine.Engine.init(allocator, 80, 24, 60, .{}) catch {
        std.debug.print("Failed to start client engine\n", .{});
        return;
    };
    defer engine.deinit();

    Client.connectToServer(allocator) catch {
        std.debug.print("Failed to connect to server\n", .{});
        return;
    };
    defer Client.disconnectFromServer();

    engine.canvas.setUpdateFn(Client.updateAndRender);
    engine.run() catch {
        std.debug.print("Client engine error\n", .{});
    };
}

fn standaloneGame(allocator: std.mem.Allocator) !void {
    var engine = try Engine.Engine.init(allocator, 150, 50, 60, .{});
    defer engine.deinit();

    const player = try Player.Player.createWASDPlayer("Player", allocator, 0, 0);
    var world = try WorldManager.WorldManager.init(Chunk.ChunkCoord{ .x = 0, .y = 0 }, 0, allocator, &engine.canvas, player);
    defer world.deinit();

    while (engine.running) {
        engine.clock.tick();
        if (try Engine.readKey()) |key| {
            if (key == 'q' or key == 27) engine.running = false;
            try world.processPlayerInput(key);
        }
        engine.canvas.clear(' ', .{ .r = 10, .g = 10, .b = 10 });
        world.updateCamera();
        world.draw();
        try engine.canvas.flushToTerminal();
        engine.clock.sleepUntilNextFrame();
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var engine = try Engine.Engine.init(allocator, 80, 24, 60, .{});
    defer engine.deinit();

    var menu = Menu.init(
        "Main Menu",
        &[_][]const u8{ "SinglePlayer", "Host", "Join", "Quit" },
        'w',
        's',
        '\n',
    );

    var choice: ?usize = null;
    while (engine.running and choice == null) {
        engine.clock.tick();
        if (try Engine.readKey()) |key| {
            if (menu.update(key)) |c| choice = c;
        }
        engine.canvas.clear(' ', .{});
        menu.draw(&engine.canvas);
        try engine.canvas.flushToTerminal();
        engine.clock.sleepUntilNextFrame();
    }

    engine.deinit();

    switch (choice orelse 3) {
        0 => try standaloneGame(allocator),
        1 => {
            //const server_thread = try std.Thread.spawn(.{}, startHostServer, .{allocator});
            //server_thread.detach();
            std.Thread.sleep(100 * std.time.ns_per_ms);
            startClient(allocator);
        },
        2 => startClient(allocator),
        3 => return,
        else => {},
    }
}


