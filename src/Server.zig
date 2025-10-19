const std = @import("std");
const posix = std.posix;
const net = std.net;
const Thread = std.Thread;
const Player = @import("Player.zig");
const WorldManager = @import("WorldManager.zig");
const Engine = @import("Engine.zig");
const Chunk = @import("Chunk.zig");

const MAX_PLAYERS = 10;

// A simple buffered writer to reduce the number of `write` syscalls.
const BufferedWriter = struct {
    socket: posix.socket_t,
    buffer: [4096]u8 = undefined,
    pos: usize = 0,

    fn print(self: *BufferedWriter, comptime format: []const u8, args: anytype) !void {
        const written = try std.fmt.bufPrint(self.buffer[self.pos..], format, args);
        self.pos += written.len;
    }

    fn flush(self: *BufferedWriter) !void {
        if (self.pos == 0) return;
        _ = try posix.write(self.socket, self.buffer[0..self.pos]);
        self.pos = 0;
    }
};

pub const GameServer = struct {
    allocator: std.mem.Allocator,
    world_manager: WorldManager.WorldManager,
    players: [MAX_PLAYERS]?PlayerInfo,
    player_count: usize,
    mutex: Thread.Mutex,
    listener: posix.socket_t,

    pub const PlayerInfo = struct {
        player: Player,
        socket: posix.socket_t,
    };

    pub fn init(allocator: std.mem.Allocator) !GameServer {
        // A canvas is needed for the world manager, but it won't be drawn.
        var dummy_canvas = try Engine.Canvas.init(allocator, 1, 1);
        const host_player = try Player.createWASDPlayer("host", allocator, 0, 0);
        var world_manager = try WorldManager.WorldManager.init(Chunk.ChunkCoord{ .x = 0, .y = 0 }, 0, allocator, &dummy_canvas, host_player);

        const address = try net.Address.parseIp("127.0.0.1", 42069);
        const listener_socket = try posix.socket(address.any.family, .STREAM, 0);

        try posix.setsockopt(listener_socket, .SOCKET, .REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(listener_socket, &address.any, address.getOsSockLen());
        try posix.listen(listener_socket, 128);

        return GameServer{
            .allocator = allocator,
            .world_manager = world_manager,
            .players = [_]?PlayerInfo{null} ** MAX_PLAYERS,
            .player_count = 0,
            .mutex = Thread.Mutex{},
            .listener = listener_socket,
        };
    }

    pub fn deinit(self: *GameServer) void {
        posix.close(self.listener);
        for (self.players) |maybe_player| {
            if (maybe_player) |player_info| {
                player_info.player.deinit();
                posix.close(player_info.socket);
            }
        }
        self.world_manager.deinit();
    }

    pub fn startServer(self: *GameServer) !void {
        std.debug.print("✅ Server listening on 127.0.0.1:42069\n", .{});
        while (true) {
            const client_socket = try posix.accept(self.listener, null, null, 0);
            const thread = try Thread.spawn(.{}, handleClient, .{ self, client_socket });
            thread.detach();
        }
    }

    fn handleClient(self: *GameServer, socket: posix.socket_t) void {
        self.handleClientError(socket) catch |err| {
            std.debug.print("Client handler error: {any}\n", .{err});
        };
        posix.close(socket);
    }

    fn handleClientError(self: *GameServer, socket: posix.socket_t) !void {
        var writer = BufferedWriter{ .socket = socket };

        self.mutex.lock();
        var player_id: ?usize = null;
        for (self.players, 0..) |*slot, i| {
            if (slot.* == null) {
                player_id = i;
                break;
            }
        }

        if (player_id == null) {
            self.mutex.unlock();
            _ = posix.write(socket, "Server full\n") catch {};
            return;
        }

        const id = player_id.?;
        const new_player = try Player.createWASDPlayer("player", self.allocator, 5, 5);
        self.players[id] = .{
            .player = new_player,
            .socket = socket,
        };
        self.player_count += 1;
        self.mutex.unlock();

        std.debug.print("Player {d} connected.\n", .{id});
        defer self.disconnectPlayer(id);

        var read_buf: [256]u8 = undefined;
        while (true) {
            const bytes_read = posix.read(socket, &read_buf) catch |err| {
                if (err == error.WouldBlock) continue;
                break; // Disconnect on read error
            };

            if (bytes_read == 0) break; // Client closed connection

            self.mutex.lock();
            if (self.players[id]) |*player_info| {
                const action = Player.InputAction.fromKey(read_buf[0]);
                try self.world_manager.handlePlayerAction(action);
            }
            self.mutex.unlock();

            // Broadcast new state to all players
            try self.broadcastGameState();
        }
    }

    fn disconnectPlayer(self: *GameServer, id: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.players[id]) |player_info| {
            player_info.player.deinit();
            self.players[id] = null;
            self.player_count -= 1;
            std.debug.print("Player {d} disconnected.\n", .{id});
        }
    }

    fn broadcastGameState(self: *GameServer) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var state_buffer = std.ArrayList(u8).init(self.allocator);
        defer state_buffer.deinit();
        var state_writer = state_buffer.writer();

        for (self.players, 0..) |maybe_player, id| {
            if (maybe_player) |player_info| {
                const p = player_info.player.getPosition();
                try state_writer.print("Player {d} {d} {d}\n", .{ id, p.x, p.y });
            }
        }
        try state_writer.writeAll("END\n");

        for (self.players) |maybe_player| {
            if (maybe_player) |player_info| {
                _ = posix.write(player_info.socket, state_buffer.items) catch {};
            }
        }
    }
};


