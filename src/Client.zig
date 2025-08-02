const std = @import("std");
const net = std.net;

pub fn connectToServer() !*net.Stream {
    // const allocator = std.heap.page_allocator;
    const address = try net.Address.parseIp("127.0.0.1", 42069);
    const stream = try net.connectTcp(address);
    std.debug.print("Connected to server\n", .{});
    return stream;
}
