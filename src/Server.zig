const std = @import("std");
const Player = @import("Player.zig");
const net = std.net;
const Thread = std.Thread;

const MAX_PLAYERS = 64;

var players: [MAX_PLAYERS]?Player = .{null} ** MAX_PLAYERS;
var player_count: usize = 0;
var mutex = Thread.Mutex{};

pub fn startServer() !void {
    var server = try net
        .StreamServer.init(.{});

    defer server.deinit();

    try server.listen(.{ .address = try net.Address.parseIp("127.0.0.1", 42069) });

    std.debug.print("Server started on 127.0.0.1:42069\n", .{});

    while (true) {
        const conn = try server.accept();
        std.debug.print("New client connected!\n", .{});

        _ = try Thread.spawn(.{}, handleClient, .{conn.stream});
    }
}

fn handleClient(stream: *net.Stream) !void {
    var id: usize = undefined;

    {
        mutex.lock();
        defer mutex.unlock();

        if (player_count >= MAX_PLAYERS) return;
        id = player_count;
        player_count += 1;

        const name = try stream.reader().readUntilDelimiterOrEofAlloc(std.heap.page_allocator, '\n', 32);
        const trimmed_name = name[0..@min(name.len, 31)];

        var p = Player{
            .id = id,
            .name = undefined,
            .stream = stream,
            .x = 0,
            .y = 0,
        };
        std.mem.copy(u8, &p.name, trimmed_name);

        players[id] = p;
    }

    var buf: [128]u8 = undefined;
    while (true) {
        const n = try stream.read(&buf);
        if (n == 0) break;

        const dx = switch (buf[0]) {
            'L' => -1.0,
            'R' => 1.0,
            else => 0.0,
        };
        const dy = switch (buf[0]) {
            'U' => -1.0,
            'D' => 1.0,
            else => 0.0,
        };

        mutex.lock();
        if (players[id]) |*p| {
            p.x += dx;
            p.y += dy;
        }
        mutex.unlock();
    }
}

fn broadcastPlayers() void {
    mutex.lock();
    defer mutex.unlock();

    var msg: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&msg);
    const writer = fbs.writer();

    for (players) |maybe_player| {
        if (maybe_player) |p| {
            _ = writer.print("{s} {d:.2} {d:.2}\n", .{ p.name, p.x, p.y }) catch continue;
        }
    }

    const out = msg[0..fbs.pos];
    for (players) |maybe_player| {
        if (maybe_player) |p| {
            _ = p.stream.writeAll(out) catch {};
        }
    }
}

pub fn main() !void {
    _ = try Thread.spawn(.{}, tickLoop, .{});
    try startServer();
}

fn tickLoop() !void {
    while (true) {
        broadcastPlayers();
        std.time.sleep(1_000_000 * 100);
    }
}
