const std = @import("std");
const posix = std.posix;
const net = std.net;
const Engine = @import("Engine.zig").Engine;
const Player = @import("Player.zig").Player;

pub const Client = struct {
    allocator: std.mem.Allocator,
    socket: ?posix.fd_t = null,
    connected: bool = false,

    pub fn init(allocator: std.mem.Allocator) Client {
        return .{ .allocator = allocator };
    }

    pub fn connect(self: *Client, address: []const u8, port: u16) !void {
        const addr = try net.Address.parseIp4(address, port);
        const stream = try net.tcpConnectToAddress(addr);
        self.socket = stream.handle;
        self.connected = true;
        std.debug.print("[Client] Connected to {s}:{d}\n", .{ address, port });
    }

    pub fn disconnect(self: *Client) void {
        if (self.socket) |fd| {
            posix.close(fd);
            self.socket = null;
            self.connected = false;
        }
    }

    pub fn updateAndRender(self: *Client, canvas: *Engine.Canvas) void {
        if (!self.connected or self.socket == null) return;
        const sock = self.socket.?;

        // Read key from player
        if (Engine.readKey() catch null) |key| {
            if (key == 'q' or key == 27) {
                self.disconnect();
                return;
            }
            _ = posix.write(sock, &[1]u8{key}) catch {};
        }

        // Receive state
        var buf: [1024]u8 = undefined;
        const n = posix.read(sock, &buf) catch |err| switch (err) {
            error.WouldBlock => return,
            else => return,
        };
        if (n == 0) return;

        // Basic example: draw whatever positions server sent
        canvas.clear(' ', .{ .r = 0, .g = 0, .b = 0 });
        var i: usize = 0;
        while (i + 2 <= n) : (i += 2) {
            const x = @as(i32, buf[i]);
            const y = @as(i32, buf[i + 1]);
            canvas.put(x, y, '@');
            canvas.fillColor(x, y, .{ .r = 255, .g = 255, .b = 255 });
        }
    }
};

pub fn main() !void {
}
