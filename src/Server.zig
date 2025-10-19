const std = @import("std");
const net = std.net;
const json = std.json;

const GameState = struct {
    tick: u64,
    players: []PlayerState,
};

const PlayerState = struct {
    id: u32,
    x: i32,
    y: i32,
    hp: i32,
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    listener: net.StreamServer,
    clients: std.ArrayList(net.StreamServer.Connection),
    world_state: GameState,
    running: bool,

    pub fn init(allocator: std.mem.Allocator) !Server {
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

    pub fn deinit(self: *Server) void {
        for (self.clients.items) |*conn| {
            conn.close();
        }
        self.clients.deinit();
        self.listener.deinit();
    }

    fn broadcast(self: *Server, msg: []const u8) void {
        for (self.clients.items) |*conn| {
            _ = conn.writer().writeAll(msg) catch {};
        }
    }

    pub fn run(self: *Server) !void {
        std.debug.print("Server started on 0.0.0.0:42069\n", .{});

        // Spawn connection acceptor thread
        var accept_thread = try std.Thread.spawn(.{}, acceptLoop, .{self});
        accept_thread.detach();

        // Main world update loop
        while (self.running) {
            std.time.sleep(50 * std.time.ns_per_ms); // 20 ticks per second
            self.world_state.tick += 1;

            // Serialize world
            var buf = std.ArrayList(u8).init(self.allocator);
            defer buf.deinit();
            try json.stringify(self.world_state, .{}, buf.writer());

            self.broadcast(buf.items);
        }
    }

    fn acceptLoop(self: *Server) void {
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

    fn clientHandler(self: *Server, conn: net.StreamServer.Connection) void {
        var reader = conn.stream.reader();
        var buf: [256]u8 = undefined;

        while (true) {
            const len = reader.read(&buf) catch break;
            if (len == 0) break;

            // TODO: process client inputs (e.g., movement, actions)
            std.debug.print("Recv from client: {s}\n", .{buf[0..len]});
        }

        std.debug.print("Client disconnected.\n", .{});
        conn.close();
    }
};

