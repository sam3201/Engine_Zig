// src/Client.zig
const std = @import("std");
const posix = std.posix;

pub fn main() !void {
    const address = try posix.sockaddr.inet4_init(42069, try posix.inet_pton4("127.0.0.1"));

    const sock_fd = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
    defer posix.close(sock_fd);

    try posix.connect(sock_fd, &address);
    std.debug.print("Connected to server!\n", .{});

    var input: [256]u8 = undefined;
    while (true) {
        const line = try std.io.getStdIn().reader().readUntilDelimiterOrEof(&input, '\n');
        if (line == null) break;
        const msg = line.?;

        if (std.mem.eql(u8, msg, "quit")) break;

        _ = try posix.write(sock_fd, msg);
        _ = try posix.write(sock_fd, "\n");

        var recv_buf: [1024]u8 = undefined;
        const n = posix.read(sock_fd, &recv_buf) catch break;
        if (n == 0) break;

        std.debug.print("Server: {s}\n", .{recv_buf[0..n]});
    }
}

