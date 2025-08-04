const eng = @import("Engine.zig");
const World = @import("World.zig");
const WorldManager = @import("WorldManager.zig");
const PlayerModule = @import("Player.zig");
const Canvas = eng.Canvas;
const std = @import("std");
const net = std.net;

fn renderGameState(
    stream: *net.Stream,
    allocator: std.mem.Allocator,
    canvas: *Canvas,
) !void {
    const reader = stream.reader();

    while (true) {
        const line = try reader.readUntilDelimiterAlloc(allocator, '\n', 1024);
        defer allocator.free(line);

        if (std.mem.eql(u8, line, "END")) break;

        var it = std.mem.tokenize(u8, line, " ");
        const label = it.next() orelse continue;
        if (!std.mem.eql(u8, label, "Player")) continue;

        const x_str = it.next() orelse continue;
        const y_str = it.next() orelse continue;

        const x = try std.fmt.parseInt(i32, x_str, 10);
        const y = try std.fmt.parseInt(i32, y_str, 10);

        canvas.put(x, y, '@');
        canvas.fillColor(x, y, eng.Color{ .r = 255, .g = 255, .b = 0 });
    }
}

pub fn connectToServer() !net.Stream {
    const address = try net.Address.parseIp("127.0.0.1", 42069);
    const stream = try net.tcpConnectToAddress(address);
    std.debug.print("Connected to server\n", .{});
    return stream;
}

pub fn disconnectFromServer(stream: *net.Stream) void {
    stream.close();
    std.debug.print("Disconnected from server\n", .{});
}

pub fn sendInput(stream: *net.Stream, input_data: []const u8) !void {
    const writer = stream.writer();
    try writer.writeAll(input_data);
    try writer.writeAll("\n");
}

pub fn receiveGameState(stream: *net.Stream, allocator: std.mem.Allocator) !void {
    const reader = stream.reader();

    while (true) {
        const line = try reader.readUntilDelimiterAlloc(allocator, '\n', 1024);
        defer allocator.free(line);

        if (std.mem.eql(u8, line, "END")) {
            break;
        }

        std.debug.print("{s}\n", .{line});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var canvas = try Canvas.init(allocator, 80, 24);

    var stream = try connectToServer();
    defer disconnectFromServer(&stream);

    while (true) {
        canvas.clear(' ', eng.Color{ .r = 0, .g = 0, .b = 0 });

        const key = eng.readKey();
        if (key) |k| std.debug.print("{s}\n", .{k});

        if (std.mem.eql(u8, key, "q")) break;
        if (std.mem.eql(u8, key, "w")) try sendInput(&stream, "w");
        if (std.mem.eql(u8, key, "s")) try sendInput(&stream, "s");
        if (std.mem.eql(u8, key, "a")) try sendInput(&stream, "a");
        if (std.mem.eql(u8, key, "d")) try sendInput(&stream, "d");

        try renderGameState(&stream, allocator, &canvas);

        canvas.present();
        std.time.sleep(16_666_666);
    }
}
