const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const address = try std.net.Address.parseIp("127.0.0.1", 8080);
    const listener = try std.net.StreamServer.listen(allocator, address);
    std.debug.print("Serving at http://127.0.0.1:8080\n", .{});

    while (true) {
        const conn = try listener.accept();
        _ = try conn.stream.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\nHello from Zig!");
        conn.stream.close();
    }
}
