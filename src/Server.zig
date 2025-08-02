const std = @import("std");
const PlayerModule = @import("Player.zig");
const Player = PlayerModule.Player;
const net = std.net;
const Thread = std.Thread;

const MAX_PLAYERS = 64;
var players: [MAX_PLAYERS]?Player = [_]?Player{null} ** MAX_PLAYERS;
var player_count: usize = 0;
var mutex = Thread.Mutex{};

pub fn startServer() !void {
    const address = try net.Address.parseIp("127.0.0.1", 42069);
    var server = try address.listen(.{
        .reuse_address = true,
    });
    defer server.deinit();

    std.debug.print("Server listening on 127.0.0.1:42069\n", .{});

    while (true) {
        const connection = server.accept() catch |err| {
            std.debug.print("Failed to accept connection: {}\n", .{err});
            continue;
        };

        const thread = try Thread.spawn(.{}, handleClient, .{connection});
        thread.detach();
    }
}

fn handleClient(connection: net.Server.Connection) void {
    defer connection.stream.close();

    const reader = connection.stream.reader();
    const writer = connection.stream.writer();

    // Find an available player slot
    mutex.lock();
    var player_id: ?usize = null;
    for (players, 0..) |maybe_player, i| {
        if (maybe_player == null) {
            player_id = i;
            break;
        }
    }

    if (player_id == null) {
        mutex.unlock();
        _ = writer.write("Server full\n") catch {};
        return;
    }

    const id = player_id.?;
    const allocator = std.heap.page_allocator;

    const new_player = PlayerModule.createWASDPlayer(allocator, 0, 0) catch {
        mutex.unlock();
        std.debug.print("Failed to create player\n", .{});
        return;
    };

    players[id] = new_player;
    player_count += 1;
    mutex.unlock();

    std.debug.print("Player {} connected\n", .{id});

    while (true) {
        var buffer: [256]u8 = undefined;
        const bytes_read = reader.read(&buffer) catch |err| {
            std.debug.print("Failed to read from client: {}\n", .{err});
            break;
        };

        if (bytes_read == 0) break;

        const input = std.mem.trim(u8, buffer[0..bytes_read], " \n\r");
        if (input.len == 0) continue;

        mutex.lock();
        if (players[id]) |*player| {
            const action = player.processInput(input[0]);
            switch (action) {
                .UP => player.move(0, -1),
                .DOWN => player.move(0, 1),
                .LEFT => player.move(-1, 0),
                .RIGHT => player.move(1, 0),
                else => {},
            }
        }
        mutex.unlock();

        sendGameState(writer) catch |err| {
            std.debug.print("Failed to send game state: {}\n", .{err});
            break;
        };
    }

    // Clean up player on disconnect
    mutex.lock();
    if (players[id]) |*player| {
        player.deinit();
    }
    players[id] = null;
    player_count -= 1;
    mutex.unlock();

    std.debug.print("Player {} disconnected\n", .{id});
}

fn sendGameState(writer: anytype) !void {
    mutex.lock();
    defer mutex.unlock();

    for (players, 0..) |maybe_player, i| {
        if (maybe_player) |player| {
            const pos = player.getPosition();
            _ = writer.print("Player {} {} {}\n", .{ i, pos.x, pos.y }) catch continue;
        }
    }
    _ = writer.write("END\n") catch {};
}

pub fn main() !void {
    try startServer();
}
