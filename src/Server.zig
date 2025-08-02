const std = @import("std");
const net = std.net;

pub fn startServer() !void {
    // const allocator = std.heap.page_allocator;

    var server = try net.StreamServer.init(.{});
    defer server.deinit();

    try server.listen(.{ .address = try net.Address.parseIp("127.0.0.1", 42069) });

    std.debug.print("Server started on 127.0.0.1:42069\n", .{});

    while (true) {
        const conn = try server.accept();
        std.debug.print("New client connected!\n", .{});

        const child = try std.Thread.spawn(.{}, handleClient, .{conn.stream});
        _ = child;
    }
}

fn handleClient(stream: *net.Stream) !void {
    var buf: [1024]u8 = undefined;
    while (true) {
        const bytes_read = try stream.read(&buf);
        if (bytes_read == 0) break;
        try stream.writeAll(buf[0..bytes_read]); // echo for now
    }
}
