// src/Server.zig

const std = @import("std");
const posix = std.posix; // Import posix
const net = std.net;
const Thread = std.Thread;
const Player = @import("Player.zig").Player;
const WorldManager = @import("WorldManager.zig");
const Engine = @import("Engine.zig");
const Chunk = @import("Chunk.zig");

var g_server: ?*GameServer = null;
const MAX_PLAYERS = 64;

const BufferedWriter = struct {
    socket: posix.socket_t,
    buffer: [4096]u8 = undefined,
    pos: usize = 0,

    fn print(self: *BufferedWriter, comptime format: []const u8, args: anytype) !void {
        const written = try std.fmt.bufPrint(self.buffer[self.pos..], format, args);
        self.pos += written.len;
    }

    fn writeAll(self: *BufferedWriter, data: []const u8) !void {
        if (self.pos + data.len > self.buffer.len) {
            try self.flush();
        }
        if (data.len > self.buffer.len) {
            _ = try posix.write(self.socket, data);
        } else {
            @memcpy(self.buffer[self.pos..][0..data.len], data);
            self.pos += data.len;
        }
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
    server_engine: Engine.Engine,
    listener: posix.socket_t, // Store the listener socket

    pub const PlayerInfo = struct {
        player: Player,
        client_id: usize,
        socket: posix.socket_t, // Store client socket directly
    };

    pub fn init(allocator: std.mem.Allocator) !GameServer {
        var canvas = try Engine.Canvas.init(allocator, 80, 24); 
        const host_player = try Player.createWASDPlayer("host", allocator, 30, 15); 
        var world_manager = try WorldManager.WorldManager.init(Chunk.ChunkCoord{ .x = 0, .y = 0 }, 0, allocator, &canvas, host_player); 
        try world_manager.updateChunks(); 
        var key_iterator = world_manager.chunks.keyIterator(); 
        while (key_iterator.next()) |coord|  { 
            if (world_manager.chunks.getPtr(coord.*)) |chunk| { 
                chunk.generate(); 
            }
        }

        const server_engine = try Engine.Engine.init(allocator, 80, 24, 30, Engine.Color{ .r = 10, .g = 10, .b = 10 }); 

        const address = try net.Address.parseIp("127.0.0.1", 42069); 
        const listener_socket = try posix.socket(address.any.family, posix.SOCK.STREAM, 0);

        try posix.setsockopt(listener_socket, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

        try posix.bind(listener_socket, &address.any, address.getOsSockLen());
        try posix.listen(listener_socket, 128); 

        return GameServer{
            .allocator = allocator,
            .world_manager = world_manager,
            .players = [_]?PlayerInfo{null} ** MAX_PLAYERS,
            .player_count = 0,
            .mutex = Thread.Mutex{},
            .server_engine = server_engine,
            .listener = listener_socket,
        };
    }

    pub fn deinit(self: *GameServer) void {
        posix.close(self.listener);
        for (&self.players) |*maybe_player| { 
            if (maybe_player.*) |*player_info| { 
                player_info.player.deinit(); 
                posix.close(player_info.socket);
            }
        }
        self.world_manager.deinit(); 
        self.server_engine.deinit();
    }

pub fn startServer(self: *GameServer) !void {
    std.debug.print("Server listening on 127.0.0.1:42069\n", .{});

    // Main accept loop
    while (true) {
        var client_addr: std.net.Address = undefined;
        var len: std.posix.socklen_t = @sizeOf(std.net.Address);
        const client_socket = posix.accept(self.listener, &client_addr.any, &len, 0) catch |err| {
            std.debug.print("Accept failed: {}\n", .{err});
            continue;
        };
        const thread = try std.Thread.spawn(.{}, handleClient, .{self, client_socket});
        thread.detach();
    }
}

    fn handleClient(self: *GameServer, socket: posix.socket_t) void {
        defer posix.close(socket);
        self.handleClientError(socket) catch |err| {
            std.debug.print("Client handler error: {any}\n", .{err});
        };
    }

    fn handleClientError(self: *GameServer, socket: posix.socket_t) !void {
        var writer = BufferedWriter{ .socket = socket };

        self.mutex.lock();
        var player_id: ?usize = null;
        for (self.players, 0..) |maybe_player, i| { 
            if (maybe_player == null) {
                player_id = i; 
                break; 
            }
        }

        if (player_id == null) {
            _ = posix.write(socket, "Server full\n") catch {}; 
            self.mutex.unlock(); 
            return;
        }

        const id = player_id.?;
        const client_id = self.player_count; 
        const new_player = try Player.createArrowPlayer("player", self.allocator, 30, 15); 

        self.players[id] = .{
            .player = new_player,
            .client_id = client_id,
            .socket = socket,
        };
        self.player_count += 1; 
        self.mutex.unlock();

        std.debug.print("Player {} connected (client_id: {})\n", .{ id, client_id });

        try self.sendGameState(&writer); 

        var read_buf: [1024]u8 = undefined;
        while (true) {
            const bytes_read = posix.read(socket, &read_buf) catch |err| {
                if (err == error.WouldBlock) continue;
                std.debug.print("Client {} disconnected (read error: {})\n", .{id, err});
                break;
            };

            if (bytes_read == 0) { 
                break;
            }

            const line = std.mem.trim(u8, read_buf[0..bytes_read], "\n\r"); 
            if (line.len == 0) continue; 

            self.mutex.lock();
            if (self.players[id]) |*player_info| {
                const action = player_info.player.processInput(line[0]); 
                try self.world_manager.handlePlayerAction(action); 
            }
            self.mutex.unlock();

            try self.sendGameState(&writer);
        }

        self.mutex.lock();
        if (self.players[id]) |*player_info| { 
            player_info.player.deinit(); 
        }
        self.players[id] = null; 
        self.player_count -= 1; 
        self.mutex.unlock();
        std.debug.print("Player {} disconnected (client_id: {})\n", .{ id, client_id }); 
    }

    fn sendGameState(self: *GameServer, writer: *BufferedWriter) !void {
        self.mutex.lock(); 
        defer self.mutex.unlock(); 

        const host_chunk = self.world_manager.getPlayerChunkCoord(); 
        var y: i32 = host_chunk.y - self.world_manager.loaded_radius; 
        while (y <= host_chunk.y + self.world_manager.loaded_radius) : (y += 1) { 
            var x: i32 = host_chunk.x - self.world_manager.loaded_radius;
            while (x <= host_chunk.x + self.world_manager.loaded_radius) : (x += 1) {
                const coord = Chunk.ChunkCoord{ .x = x, .y = y }; 
                if (self.world_manager.chunks.get(coord)) |chunk| { 
                    var cy: i32 = 0;
                    while (cy < Chunk.CHUNK_HEIGHT) : (cy += 1) {
                        var cx: i32 = 0;
                        while (cx < Chunk.CHUNK_WIDTH) : (cx += 1) {
                            const tile = chunk.getTile(cx, cy); 
                            const world_x = x * Chunk.CHUNK_WIDTH + cx; 
                            const world_y = y * Chunk.CHUNK_HEIGHT + cy; 
                            try writer.print("Tile {d} {d} {d}\n", .{ world_x, world_y, @intFromEnum(tile) }); 
                        }
                    }
                }
            }
        }

        for (self.players) |maybe_player| { 
            if (maybe_player) |player_info| { 
                const pos = player_info.player.getPosition();
                const is_host = player_info.client_id == 0;
                try writer.print("Player {d} {d} {s}\n", .{ pos.x, pos.y, if (is_host) "true" else "false" });
            }
        }
        try writer.writeAll("END\n");
        try writer.flush();
    }
};

pub fn main() !void {
    var server = try GameServer.init(std.heap.page_allocator);
    defer server.deinit();
    try server.startServer();
}
