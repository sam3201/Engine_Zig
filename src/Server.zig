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

// A simple buffered writer to reduce syscalls.
const BufferedWriter = struct {
    socket: posix.socket_t,
    buffer: [4096]u8 = undefined,
    pos: usize = 0,

    fn print(self: *BufferedWriter, comptime format: []const u8, args: anytype) !void {
        const remaining_space = self.buffer.len - self.pos;
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

        // Set SO_REUSEADDR to allow the address to be reused immediately after the server closes
        try posix.setsockopt(listener_socket, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

        try posix.bind(listener_socket, &address.any, address.getOsSockLen());
        try posix.listen(listener_socket, 128); // 128 is the backlog queue size

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

        const server_thread = try Thread.spawn(.{}, runServerEngine, .{self}); 
        defer server_thread.join(); [cite: 316]

        while (true) {
            var client_address: net.Address = undefined;
            var client_address_len: posix.socklen_t = @sizeOf(net.Address);
            const client_socket = posix.accept(self.listener, &client_address.any, &client_address_len, 0) catch |err| {
                [cite_start]std.debug.print("Failed to accept connection: {}\n", .{err}); [cite: 317]
                [cite_start]continue; [cite: 318]
            };

            [cite_start]const thread = try Thread.spawn(.{}, handleClient, .{ self, client_socket }); [cite: 319]
            [cite_start]thread.detach(); [cite: 319]
        }
    }

    fn runServerEngine(self: *GameServer) void {
        [cite_start]g_server = self; [cite: 322]
        [cite_start]self.server_engine.canvas.setUpdateFn(updateCallback); [cite: 322]
        self.server_engine.run() catch |err| {
            [cite_start]std.debug.print("Server engine error: {}\n", .{err}); [cite: 323]
        };
    }

    fn updateCallback(canvas: *Engine.Canvas) void {
        if (g_server) |server| [cite_start]{ [cite: 320]
            [cite_start]server.mutex.lock(); [cite: 321]
            [cite_start]defer server.mutex.unlock(); [cite: 321]

            [cite_start]server.world_manager.draw(); [cite: 321]
            [cite_start]drawServerOverview(canvas, server); [cite: 321]
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
        for (self.players, 0..) |maybe_player, i| [cite_start]{ [cite: 325]
            if (maybe_player == null) {
                [cite_start]player_id = i; [cite: 326]
                [cite_start]break; [cite: 326]
            }
        }

        if (player_id == null) {
            [cite_start]_ = posix.write(socket, "Server full\n") catch {}; [cite: 327]
            [cite_start]self.mutex.unlock(); [cite: 327]
            return;
        }

        const id = player_id.?;
        [cite_start]const client_id = self.player_count; [cite: 328]
        [cite_start]const new_player = try Player.createArrowPlayer("player", self.allocator, 30, 15); [cite: 329]

        self.players[id] = .{
            .player = new_player,
            .client_id = client_id,
            .socket = socket,
        };
        [cite_start]self.player_count += 1; [cite: 330]
        self.mutex.unlock();

        std.debug.print("Player {} connected (client_id: {})\n", .{ id, client_id });

        [cite_start]try self.sendGameState(&writer); [cite: 331]

        var read_buf: [1024]u8 = undefined;
        while (true) {
            const bytes_read = posix.read(socket, &read_buf) catch |err| {
                if (err == error.WouldBlock) continue;
                std.debug.print("Client {} disconnected (read error: {})\n", .{id, err});
                break;
            };

            if (bytes_read == 0) { // Client closed connection
                break;
            }

            [cite_start]const line = std.mem.trim(u8, read_buf[0..bytes_read], "\n\r"); [cite: 338]
            [cite_start]if (line.len == 0) continue; [cite: 338]

            self.mutex.lock();
            if (self.players[id]) |*player_info| {
                [cite_start]const action = player_info.player.processInput(line[0]); [cite: 339]
                [cite_start]try self.world_manager.handlePlayerAction(action); [cite: 339]
            }
            self.mutex.unlock();

            try self.sendGameState(&writer);
        }

        self.mutex.lock();
        if (self.players[id]) |*player_info| [cite_start]{ [cite: 341]
            [cite_start]player_info.player.deinit(); [cite: 342]
        }
        [cite_start]self.players[id] = null; [cite: 343]
        [cite_start]self.player_count -= 1; [cite: 343]
        self.mutex.unlock();
        [cite_start]std.debug.print("Player {} disconnected (client_id: {})\n", .{ id, client_id }); [cite: 343]
    }

    fn sendGameState(self: *GameServer, writer: *BufferedWriter) !void {
        [cite_start]self.mutex.lock(); [cite: 344]
        [cite_start]defer self.mutex.unlock(); [cite: 344]

        [cite_start]const host_chunk = self.world_manager.getPlayerChunkCoord(); [cite: 345]
        [cite_start]var y: i32 = host_chunk.y - self.world_manager.loaded_radius; [cite: 345]
        [cite_start]while (y <= host_chunk.y + self.world_manager.loaded_radius) : (y += 1) { [cite: 345]
            [cite_start]var x: i32 = host_chunk.x - self.world_manager.loaded_radius; [cite: 346]
            while (x <= host_chunk.x + self.world_manager.loaded_radius) : (x += 1) {
                [cite_start]const coord = Chunk.ChunkCoord{ .x = x, .y = y }; [cite: 347]
                if (self.world_manager.chunks.get(coord)) |chunk| [cite_start]{ [cite: 348]
                    var cy: i32 = 0;
                    while (cy < Chunk.CHUNK_HEIGHT) : (cy += 1) {
                        var cx: i32 = 0;
                        while (cx < Chunk.CHUNK_WIDTH) : (cx += 1) {
                            [cite_start]const tile = chunk.getTile(cx, cy); [cite: 350]
                            [cite_start]const world_x = x * Chunk.CHUNK_WIDTH + cx; [cite: 351]
                            [cite_start]const world_y = y * Chunk.CHUNK_HEIGHT + cy; [cite: 351]
                            [cite_start]try writer.print("Tile {d} {d} {d}\n", .{ world_x, world_y, @intFromEnum(tile) }); [cite: 352]
                        }
                    }
                }
            }
        }

        // Send player positions
        for (self.players, 0..) |maybe_player, i| [cite_start]{ [cite: 353]
            if (maybe_player) |player_info| [cite_start]{ [cite: 354]
                [cite_start]const pos = player_info.player.getPosition(); [cite: 355]
                const is_host = player_info.client_id == 0;
                try writer.print("Player {d} {d} {s}\n", .{ pos.x, pos.y, if (is_host) "true" else "false" });
            }
        }
        try writer.writeAll("END\n");
        try writer.flush();
    }
};

fn drawServerOverview(engine: *Engine.Canvas, server: *GameServer) void {
    const white = Engine.Color{ .r = 255, .g = 255, .b = 255 };
    const green = Engine.Color{ .r = 0, .g = 255, .b = 0 };
    const blue = Engine.Color{ .r = 100, .g = 150, .b = 255 };

    // Server title
    const title = "OPEN WORLD GAME SERVER";
    const title_start = (80 - title.len) / 2;
    for (title, 0..) |char, i| {
        engine.put(@intCast(title_start + i), 2, char);
        engine.fillColor(@intCast(title_start + i), 2, green);
    }

    // CPU info
    const cpu_count = Thread.getCpuCount() catch 1;
    const cpu_text = std.fmt.allocPrint(std.heap.page_allocator, "Available CPU Cores: {d}", .{cpu_count}) catch return;
    defer std.heap.page_allocator.free(cpu_text);

    for (cpu_text, 0..) |char, i| {
        engine.put(@intCast(i + 5), 5, char);
        engine.fillColor(@intCast(i + 5), 5, white);
    }

    // Active players count
    const instance_text = std.fmt.allocPrint(std.heap.page_allocator, "Active Players: {d}", .{server.player_count}) catch return;
    defer std.heap.page_allocator.free(instance_text);

    for (instance_text, 0..) |char, i| {
        engine.put(@intCast(i + 5), 7, char);
        engine.fillColor(@intCast(i + 5), 7, blue);
    }

    // List players
    var y_offset: i32 = 10;
    for (server.players) |maybe_player| {
        if (y_offset >= 20) break;
        if (maybe_player) |player_info| {
            const pos = player_info.player.getPosition();
            const status_text = std.fmt.allocPrint(std.heap.page_allocator, "Player {d}: ({d}, {d}) {s}", .{ player_info.client_id, pos.x, pos.y, if (player_info.client_id == 0) "(Host)" else "" }) catch continue;
            defer std.heap.page_allocator.free(status_text);

            for (status_text, 0..) |char, j| {
                if (j >= 75) break;
                engine.put(@intCast(j + 5), y_offset, char);
                engine.fillColor(@intCast(j + 5), y_offset, if (player_info.client_id == 0) green else blue);
            }
            y_offset += 1;
        }
    }

    // Instructions
    const instructions = [_][]const u8{
        "Press 'q' to quit server and disconnect all players",
        "Host player sets difficulty level",
        "Connect via client to 127.0.0.1:42069",
    };

    y_offset = 22;
    for (instructions) |instruction| {
        if (y_offset >= 24) break;
        for (instruction, 0..) |char, i| {
            if (i >= 75) break;
            engine.put(@intCast(i + 2), y_offset, char);
            engine.fillColor(@intCast(i + 2), y_offset, white);
        }
        y_offset += 1;
    }
}

pub fn main() !void {
    var server = try GameServer.init(std.heap.page_allocator);
    defer server.deinit();
    try server.startServer();
}
