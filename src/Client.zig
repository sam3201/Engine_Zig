const std = @import("std");
const net = std.net;

pub fn connectToServer() !*net.Stream {
    // const allocator = std.heap.page_allocator;
    const address = try net.Address.parseIp("127.0.0.1", 42069);
    const stream = try net.tcpConnectToAddress(address);
    std.debug.print("Connected to server\n", .{});
    return stream;
}

pub fn disconnectFromServer(stream: *net.Stream) void {
    std.debug.print("Disconnected from server\n", .{});
    stream.close();
}

pub fn sendToServer(stream: *net.Stream, message: []const u8) !void {
    try stream.writeAll(message);
}

pub fn receiveFromServer(stream: *net.Stream) ![]const u8 {
    return stream.readAllAlloc(std.heap.page_allocator, 1024);
}

pub fn main() !void {
    const stream = try connectToServer();
    defer disconnectFromServer(stream);
    while (true) {
        const message = try receiveFromServer(stream);
        std.debug.print("Received message: {s}\n", .{message});
    }
}
