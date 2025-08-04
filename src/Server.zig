// src/Server.zig

const std = @import("std");
const net = std.net;
const Thread = std.Thread;
const PlayerModule = @import("Player.zig");
const Player = PlayerModule.Player;
const WorldManager = @import("WorldManager.zig");
const Engine = @import("Engine.zig");
const Chunk = @import("Chunk.zig");

const MAX_PLAYERS = 64;

pub const GameServer = struct {
    allocator: std.mem.Allocator,
    world_manager: WorldManager.WorldManager,
    players: [MAX_PLAYERS]?PlayerInfo,
    player_count: usize,
    mutex: Thread.Mutex,
    server_engine: Engine.Engine,
    next_client_id: u32,

    pub const PlayerInfo = struct {
        player: Player,
        client_id: u32,
        connection: net.Server.Connection,
        is_host: bool,
    };

    pub fn init(allocator: std.mem.Allocator) !GameServer {
        const canvas = try Engine.Canvas.init(allocator, 80, 24);
        const host_player = try PlayerModule.createWASDPlayer(allocator, 30, 15);
        var world_manager = try WorldManager.WorldManager.init(allocator, &canvas, host_player);

        // Generate initial chunks
        try world_manager.updateChunks();
        var key_iterator = world_manager.chunks.keyIterator();
        while (key_iterator.next()) |coord| {
            if (world_manager.chunks.getPtr(coord.*)) |chunk| {
                chunk.generate(host_player.getLevel());
            }
        }

        const server_engine = try Engine.Engine.init(allocator, 80, 24, 30, Engine.Color{ .r = 10, .g = 10, .b = 10 });

        return GameServer{
            .allocator = allocator,
            .world_manager = world_manager,
            .players = [_]?PlayerInfo{null} ** MAX_PLAYERS,
            .player_count = 0,
            .mutex = Thread.Mutex{},
            .server_engine = server_engine,
            .next_client_id = 0,
        };
    }

    pub fn deinit(self: *GameServer) void {
        for (&self.players) |*maybe_player| {
            if (maybe_player.*) |*player_info| {
                player_info.player.deinit();
                player_info.connection.stream.close();
            }
        }

        self.world_manager.deinit();
        self.server_engine.deinit();
    }

    pub fn startServer(self: *GameServer) !void {
        const address = try net.Address.parseIp("127.0.0.1", 42069);
        var server = try address.listen(.{ .reuse_address = true });
        defer server.deinit();

        std.debug.print("Server listening on 127.0.0.1:42069\n", .{});

        // Add host player
        self.mutex.lock();
        const host_id = self.next_client_id;
        self.next_client_id += 1;
        self.players[host_id] = .{
            .player = self.world_manager.player,
            .client_id = host_id,
            .connection = undefined, // Host doesn't need a connection
            .is_host = true,
        };
        self.player_count += 1;
        self.mutex.unlock();

        // Start server rendering
        const server_thread = try Thread.spawn(.{}, runServerEngine, .{self});
        defer server_thread.join();

        // Handle client connections
        while (true) {
            const connection = server.accept() catch |err| {
                std.debug.print("Failed to accept connection: {}\n", .{err});
                continue;
            };

            const thread = try Thread.spawn(.{}, handleClient, .{ self, connection });
            thread.detach();
        }
    }

    fn runServerEngine(self: *GameServer) void {
        // FIX 2: Create a proper context struct with update method
        const ServerContext = struct {
            server: *GameServer,

            pub fn update(Self: *@This(), canvas: *Engine.Canvas) void {
                Self.server.mutex.lock();
                defer Self.server.mutex.unlock();

                Self.server.world_manager.draw();
                drawServerOverview(canvas, Self.server);
            }
        };

        var context = ServerContext{ .server = self };

        // FIX 2: Pass the context properly to setUpdateFn
        self.server_engine.canvas.setUpdateFn(&context.update);
        self.server_engine.run() catch |err| {
            std.debug.print("Server engine error: {}\n", .{err});
        };
    }

    // FIX 3: Change return type to handle errors properly
    fn handleClient(self: *GameServer, connection: net.Server.Connection) !void {
        defer connection.stream.close();

        const reader = connection.stream.reader();
        const writer = connection.stream.writer();

        // Create new player
        self.mutex.lock();
        var player_id: ?usize = null;
        for (self.players, 0..) |maybe_player, i| {
            if (maybe_player == null) {
                player_id = i;
                break;
            }
        }

        if (player_id == null) {
            _ = writer.write("Server full\n") catch {};
            self.mutex.unlock();
            return;
        }

        const id = player_id.?;
        const client_id = self.next_client_id;
        self.next_client_id += 1;

        const new_player = PlayerModule.createVimPlayer(self.allocator, 30, 15) catch {
            _ = writer.write("Failed to create player\n") catch {};
            self.mutex.unlock();
            return;
        };

        self.players[id] = .{
            .player = new_player,
            .client_id = client_id,
            .connection = connection,
            .is_host = false,
        };
        self.player_count += 1;
        self.mutex.unlock();

        std.debug.print("Player {} connected (client_id: {})\n", .{ id, client_id });

        while (true) {
            var buffer: [256]u8 = undefined;
            const bytes_read = reader.read(&buffer) catch |err| {
                std.debug.print("Failed to read from client {}: {}\n", .{ client_id, err });
                break;
            };

            if (bytes_read == 0) break;

            const input = std.mem.trim(u8, buffer[0..bytes_read], " \n\r");
            if (input.len == 0) continue;

            self.mutex.lock();
            if (self.players[id]) |*player_info| {
                const action = player_info.player.processInput(input[0]);
                // FIX 3: Now properly handles the error return from handlePlayerAction
                try self.world_manager.handlePlayerAction(action);
            }
            self.mutex.unlock();

            try self.sendGameState(writer);
        }

        // Clean up player on disconnect
        self.mutex.lock();
        if (self.players[id]) |*player_info| {
            player_info.player.deinit();
        }
        self.players[id] = null;
        self.player_count -= 1;
        self.mutex.unlock();

        std.debug.print("Player {} disconnected (client_id: {})\n", .{ id, client_id });
    }

    fn sendGameState(self: *GameServer, writer: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Send chunk data around the host player
        const host_chunk = self.world_manager.getPlayerChunkCoord();
        var y: i32 = host_chunk.y - self.world_manager.loaded_radius;
        while (y <= host_chunk.y + self.world_manager.loaded_radius) : (y += 1) {
            var x: i32 = host_chunk.x - self.world_manager.loaded_radius;
            while (x <= host_chunk.x + self.world_manager.loaded_radius) : (x += 1) {
                const coord = Chunk.ChunkCoord{ .x = x, .y = y };
                if (self.world_manager.chunks.get(coord)) |chunk| {
                    for (0..@intCast(Chunk.CHUNK_SIZE)) |cy| {
                        for (0..@intCast(Chunk.CHUNK_SIZE)) |cx| {
                            const tile = chunk.getTile(@intCast(cx), @intCast(cy));
                            const world_x = x * Chunk.CHUNK_SIZE + @as(i32, @intCast(cx));
                            const world_y = y * Chunk.CHUNK_SIZE + @as(i32, @intCast(cy));
                            try writer.print("Tile {} {} {} {}\n", .{ world_x, world_y, @intFromEnum(tile), chunk.difficulty_level });
                        }
                    }
                }
            }
        }

        // Send player positions
        for (self.players, 0..) |maybe_player, i| {
            if (maybe_player) |player_info| {
                const pos = player_info.player.getPosition();
                try writer.print("Player {} {} {} {}\n", .{ i, pos.x, pos.y, player_info.is_host });
            }
        }
        _ = try writer.write("END\n");
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
            const status_text = std.fmt.allocPrint(std.heap.page_allocator, "Player {d}: ({d}, {d}) {s}", .{ player_info.client_id, pos.x, pos.y, if (player_info.is_host) "(Host)" else "" }) catch continue;
            defer std.heap.page_allocator.free(status_text);

            for (status_text, 0..) |char, j| {
                if (j >= 75) break;
                engine.put(@intCast(j + 5), y_offset, char);
                engine.fillColor(@intCast(j + 5), y_offset, if (player_info.is_host) green else blue);
            }
            y_offset += 1;
        }
    }

    // Instructions
    const instructions = [_][]const u8{
        "Press 'q' to quit server and disconnect all players",
        "Host player sets difficulty level",
        "Connect via client to 127.0.0.1:42069",
        // TODO: Add save game functionality here in future
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
