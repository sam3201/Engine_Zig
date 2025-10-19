// src/Server.zig
const std = @import("std");
const posix = std.posix;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const address = try posix.sockaddr.inet4_init(42069, posix.INADDR_ANY);
    const server_fd = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
    defer posix.close(server_fd);

    try posix.setsockopt(server_fd, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(server_fd, &address);
    try posix.listen(server_fd, 8);

    std.debug.print("Server listening on port 42069...\n", .{});

    while (true) {
        var client_addr: posix.sockaddr = undefined;
        var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);
        const conn_fd = posix.accept(server_fd, &client_addr, &addr_len) catch {
            std.debug.print("Failed to accept connection\n", .{});
            continue;
        };
        std.debug.print("Client connected!\n", .{});

        // Handle connection
        handleClient(conn_fd, allocator) catch |err| {
            std.debug.print("Client error: {}\n", .{err});
        };
        posix.close(conn_fd);
    }
}

fn handleClient(fd: posix.fd_t, allocator: std.mem.Allocator) !void {
    var buffer: [1024]u8 = undefined;

    while (true) {
        const bytes_read = posix.read(fd, &buffer) catch |err| switch (err) {
            error.ConnectionResetByPeer, error.BrokenPipe => break,
            else => return err,
        };

        if (bytes_read == 0) break;

        // For now, just echo back
        const slice = buffer[0..bytes_read];
        _ = try posix.write(fd, slice);
        std.debug.print("Received: {s}\n", .{slice});
    }
}

