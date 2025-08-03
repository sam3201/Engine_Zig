const eng = @import("Engine.zig");
const PlayerModule = @import("Player.zig");
const Canvas = eng.Canvas;
const input = eng.input;
const std = @import("std");
const net = std.net;

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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stream = try connectToServer();
    defer disconnectFromServer(&stream);

    var canvas = try Canvas.init(allocator, 80, 24); // adjust to your terminal
    defer canvas.deinit();

    var input_state = input.InputState{};
    try input_state.init();

    while (true) {
        canvas.clear();

        try input_state.poll();

        if (input_state.isKeyPressed('q')) break;

        if (input_state.isKeyPressed('w')) try sendInput(&stream, "w");
        if (input_state.isKeyPressed('s')) try sendInput(&stream, "s");
        if (input_state.isKeyPressed('a')) try sendInput(&stream, "a");
        if (input_state.isKeyPressed('d')) try sendInput(&stream, "d");

        // Receive new game state and draw
        try renderGameState(&stream, allocator, &canvas);

        canvas.present();
        std.time.sleep(16_666_666); // ~60 FPS
    }
}
