const std = @import("std");
const net = std.net;
const json = std.json;
const posix = std.posix;

const PlayerState = struct {
    id: u32,
    x: i32,
    y: i32,
    hp: i32,
};

const GameState = struct {
    tick: u64,
    players: []PlayerState,
};

pub const GameServer = struct {
    allocator: std.mem.Allocator,
    listener: std.posix.fd_t,
    clients: std.ArrayList(net.StreamServer.Connection),
    world_state: GameState,
    running: bool,

    pub fn init(allocator: std.mem.Allocator) !GameServer {
        const address = try net.Address.parseIp4("0.0.0.0", 42069);
        var listener = try net.StreamServer.init(.{});
        try listener.listen(address);

        return .{
            .allocator = allocator,
            .listener = listener,
            .clients = std.ArrayList(net.StreamServer.Connection).init(allocator),
            .world_state = .{ .tick = 0, .players = &[_]PlayerState{} },
            .running = true,
        };
    }

    pub fn deinit(self: *GameServer) void {
        for (self.clients.items) |*conn| conn.close();
        self.clients.deinit();
        self.listener.deinit();
    }

    fn broadcast(self: *GameServer, msg: []const u8) void {
        for (self.clients.items) |*conn| {
            const fd = conn.stream.handle;
            _ = posix.write(fd, msg) catch {};
        }
    }

    pub fn run(self: *GameServer) !void {
        std.debug.print("Server started on 0.0.0.0:42069\n", .{});
        var accept_thread = try std.Thread.spawn(.{}, acceptLoop, .{self});
        accept_thread.detach();

        while (self.running) {
            std.time.sleep(50 * std.time.ns_per_ms);
            self.world_state.tick += 1;

            var buf = std.ArrayList(u8).init(self.allocator);
            defer buf.deinit();
            try json.stringify(self.world_state, .{}, buf.writer());

            self.broadcast(buf.items);
        }
    }

    fn acceptLoop(self: *GameServer) void {
        while (self.running) {
            const conn = self.listener.accept() catch |err| {
                std.debug.print("Accept error: {}\n", .{err});
                continue;
            };

            std.debug.print("Client connected!\n", .{});
            self.clients.append(conn) catch continue;

            const thread = std.Thread.spawn(.{}, clientHandler, .{self, conn}) catch continue;
            thread.detach();
        }
    }

    fn clientHandler(conn: net.StreamServer.Connection) void {
        const fd = conn.stream.handle;
        var buf: [512]u8 = undefined;

        while (true) {
            const len = posix.read(fd, &buf) catch break;
            if (len == 0) break;
            std.debug.print("Client says: {s}\n", .{buf[0..len]});
        }

        std.debug.print("Client disconnected.\n", .{});
        conn.close();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try GameServer.init(allocator);
    defer server.deinit();

    try server.run();
}

