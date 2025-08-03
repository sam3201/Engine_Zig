const eng = @import("Engine.zig");
const PlayerModule = @import("Player.zig");
const Canvas = eng.Canvas;
const input = eng.input;
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

pub fn sendInput(stream: *net.Stream, input: []const u8) !void {
    const writer = stream.writer();
    try writer.writeAll(input);
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
    while (true) {
        var canvas.clear();

        try input_state.poll();

        if (input_state.isKeyPressed('q')) break;

        if (input_state.isKeyPressed('w')) try sendInput(&stream, "w");
        if (input_state.isKeyPressed('s')) try sendInput(&stream, "s");
        if (input_state.isKeyPressed('a')) try sendInput(&stream, "a");
        if (input_state.isKeyPressed('d')) try sendInput(&stream, "d");

        try renderGameState(&stream, allocator, &canvas);

        canvas.present();
        std.time.sleep(16_666_666); // 60fps
    }
}
