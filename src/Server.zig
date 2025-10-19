const std = @import("std");
const net = std.net;
const posix = std.posix;
const WorldManager = @import("WorldManager.zig").WorldManager;
const Player = @import("Player.zig").Player;

pub const Server = struct {
    allocator: std.mem.Allocator,
    listener: std.posix.Socket,
    clients: std.ArrayList(net.StreamServer.Connection),
    world_manager: WorldManager,
    running: bool,

    pub fn init(allocator: std.mem.Allocator) !Server {
        var listener = try net.StreamServer.init(.{});
        const address = try net.Address.parseIp4("0.0.0.0", 42069);
        try listener.listen(address);

        std.debug.print("[Server] Listening on 0.0.0.0:42069\n", .{});

        return Server{
            .allocator = allocator,
            .listener = listener,
            .clients = try std.ArrayList(net.StreamServer.Connection).initCapacity(allocator, 8),
            .world_manager = try WorldManager.init(allocator),
            .running = true,
        };
    }

    pub fn deinit(self: *Server) void {
        for (self.clients.items) |*c| {
            c.stream.close();
        }
        self.listener.deinit();
        self.clients.deinit();
        self.world_manager.deinit();
    }

    fn broadcast(self: *Server, msg: []const u8) void {
        for (self.clients.items) |*c| {
            _ = posix.write(c.stream.handle, msg) catch {};
        }
    }

    fn handleClient(self: *Server, conn: net.StreamServer.Connection) void {
        var buffer: [256]u8 = undefined;
        while (self.running) {
            const n = posix.read(conn.stream.handle, &buffer) catch |err| switch (err) {
                error.WouldBlock => continue,
                else => return,
            };
            if (n == 0) return;

            for (buffer[0..n]) |key| {
                self.world_manager.processPlayerInput(key) catch {};
            }

            // After processing input, send updated positions
            var state_buf: [1024]u8 = undefined;
            const len = self.world_manager.serializeState(&state_buf) catch continue;
            _ = posix.write(conn.stream.handle, state_buf[0..len]) catch {};
        }
    }

    pub fn run(self: *Server) !void {
        var poll: [1]posix.pollfd = .{posix.pollfd{
            .fd = self.listener.socket.fd,
            .events = posix.POLL.IN,
            .revents = 0,
        }};

        while (self.running) {
            const n = try posix.poll(&poll, -1);
            if (n > 0 and (poll[0].revents & posix.POLL.IN) != 0) {
                const conn = try self.listener.accept();
                std.debug.print("[Server] Client connected!\n", .{});
                try self.clients.append(conn);
                std.Thread.spawn(.{}, Server.clientThread, .{self, conn}) catch {};
            }
        }
    }

    fn clientThread(self: *Server, conn: net.StreamServer.Connection) void {
        self.handleClient(conn);
    }
};

pub fn main() !void {

}
