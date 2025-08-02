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

    var stream = connectToServer() catch |err| {
        std.debug.print("Failed to connect: {}\n", .{err});
        return;
    };
    defer disconnectFromServer(&stream);

    // Simple test - send some commands
    try sendInput(&stream, "RIGHT");
    try receiveGameState(&stream, allocator);

    try sendInput(&stream, "UP");
    try receiveGameState(&stream, allocator);

    std.debug.print("Client test completed\n", .{});
}
