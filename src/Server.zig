const std = @import("std");
const Player = @import("Player.zig");
const net = std.net;
const Thread = std.Thread;

const MAX_PLAYERS = 64;

var players: [MAX_PLAYERS]?Player = .{null} ** MAX_PLAYERS;
var player_count: usize = 0;
var mutex = Thread.Mutex{};

const Player = struct {
    id: usize,
    x: f32,
    y: f32,
    vx: f32 = 0.0,
    vy: f32 = 0.0,
};

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

    mutex.lock();
    defer mutex.unlock();

    if (player_count >= MAX_PLAYERS) {
        _ = writer.write("Server full\n") catch {};
        return;
    }

    const player_id = player_count;
    const allocator = std.heap.page_allocator;

    const maybe_player = Player.createWASDPlayer(allocator, 0.0, 0.0) catch {
        std.debug.print("Failed to create player\n", .{});
        return;
    };
    players[player_id] = maybe_player;
    player_count += 1;

    std.debug.print("Player {} connected\n", .{player_id});

    while (true) {
        var buffer: [256]u8 = undefined;
        const bytes_read = reader.read(&buffer) catch |err| {
            std.debug.print("Failed to read from client: {}\n", .{err});
            break;
        };

        if (bytes_read == 0) break;

        const input = std.mem.trim(u8, buffer[0..bytes_read], " \n\r");

        if (std.mem.eql(u8, input, "UP")) {
            if (players[player_id]) |*p| p.y -= 1.0;
        } else if (std.mem.eql(u8, input, "DOWN")) {
            if (players[player_id]) |*p| p.y += 1.0;
        } else if (std.mem.eql(u8, input, "LEFT")) {
            if (players[player_id]) |*p| p.x -= 1.0;
        } else if (std.mem.eql(u8, input, "RIGHT")) {
            if (players[player_id]) |*p| p.x += 1.0;
        }

        sendGameState(writer) catch |err| {
            std.debug.print("Failed to send game state: {}\n", .{err});
            break;
        };
    }

    mutex.lock();
    players[player_id] = null;
    player_count -= 1;
    mutex.unlock();

    std.debug.print("Player {} disconnected\n", .{player_id});
}

fn sendGameState(writer: anytype) !void {
    mutex.lock();
    defer mutex.unlock();

    for (players, 0..) |maybe_player, i| {
        if (maybe_player) |p| {
            _ = writer.print("Player {} {d:.2} {d:.2}\n", .{ i, p.x, p.y }) catch continue;
        }
    }
    _ = writer.write("END\n") catch {};
}

pub fn main() !void {
    try startServer();
}
