const std = @import("std");
const posix = std.posix;
const net = std.net;
const Thread = std.Thread;
const Player = @import("Player.zig").Player;
const WorldManager = @import("WorldManager.zig");
const Chunk = @import("Chunk.zig");
const Engine = @import("Engine.zig");

const MAX_PLAYERS = 10;

pub const GameServer = struct {
    allocator: std.mem.Allocator,
    world_manager: WorldManager,
    players: [MAX_PLAYERS]?PlayerInfo,
    player_count: u32 = 0,
    mutex: Thread.Mutex,
    listener: posix.socket_t,

    pub const PlayerInfo = struct {
        player: *Player,
        socket: posix.socket_t,
        id: u32,
    };

    pub fn init(allocator: std.mem.Allocator) !GameServer {
        // The server is headless, but WorldManager needs a canvas for its logic.
        var dummy_canvas = try Engine.Canvas.init(allocator, 1, 1);
        // The host player is managed by the WorldManager.
        const host_player = try Player.createWASDPlayer("host", allocator, 10, 10);

        var world_manager = try WorldManager.init(Chunk.ChunkCoord.init(0, 0), 0, allocator, &dummy_canvas, host_player);

        const address = try net.Address.parseIp("127.0.0.1", 42069);
        const listener_socket = try posix.socket(address.any.family, posix.SOCK.STREAM, 0);

        try posix.setsockopt(listener_socket, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(listener_socket, &address.any, address.getOsSockLen());
        try posix.listen(listener_socket, 128);

        return GameServer{
            .allocator = allocator,
            .world_manager = world_manager,
            .players = [_]?PlayerInfo{null} ** MAX_PLAYERS,
            .mutex = Thread.Mutex{},
            .listener = listener_socket,
        };
    }

    pub fn deinit(self: *GameServer) void {
        posix.close(self.listener);
        // Deinit all connected players
        for (self.players) |maybe_player| {
            if (maybe_player) |player_info| {
                player_info.player.deinit();
                posix.close(player_info.socket);
            }
        }
        // The world manager owns and deinits the host player
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
        handleClientError(self, socket) catch |err| {
            std.debug.print("Client handler error: {any}\n", .{err});
        };
        posix.close(socket);
    }

    fn handleClientError(self: *GameServer, socket: posix.socket_t) !void {
        self.mutex.lock();
        var player_id: ?u32 = null;
        for (0..MAX_PLAYERS) |i| {
            if (self.players[i] == null) {
                player_id = @intCast(i);
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
        self.players[@intCast(id)] = .{
            .player = new_player,
            .socket = socket,
            .id = id,
        };
        self.player_count += 1;
        self.mutex.unlock();

        std.debug.print("Player {d} connected.\n", .{id});
        defer self.disconnectPlayer(id);

        var read_buf: [1]u8 = undefined;
        while (true) {
            const bytes_read = posix.read(socket, &read_buf) catch |err| {
                if (err == error.WouldBlock) continue;
                break;
            };
            if (bytes_read == 0) break;

            const action = Player.InputAction.fromKey(read_buf[0]);

            self.mutex.lock();
            // In a real game, you would apply the action to the specific player.
            // For this simplified version, all inputs control the host player.
            try self.world_manager.handlePlayerAction(action);
            self.mutex.unlock();

            try self.broadcastGameState();
        }
    }

    fn disconnectPlayer(self: *GameServer, id: u32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.players[@intCast(id)]) |player_info| {
            player_info.player.deinit();
            self.players[@intCast(id)] = null;
            self.player_count -= 1;
            std.debug.print("Player {d} disconnected.\n", .{id});
        }
    }

    fn broadcastGameState(self: *GameServer) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var buffer: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buffer);
        const writer = stream.writer();

        // Broadcast host player (ID 0)
        const host_pos = self.world_manager.player.getPosition();
        try writer.print("Player 0 {d} {d}\n", .{ host_pos.x, host_pos.y });

        // Broadcast other players
        for (self.players) |maybe_player| {
            if (maybe_player) |player_info| {
                const p = player_info.player.getPosition();
                try writer.print("Player {d} {d} {d}\n", .{ player_info.id, p.x, p.y });
            }
        }
        try writer.writeAll("END\n");

        const message = stream.getWritten();
        for (self.players) |maybe_player| {
            if (maybe_player) |player_info| {
                _ = posix.write(player_info.socket, message) catch {};
            }
        }
    }
};

// Dummy main for build system
pub fn main() !void {}


