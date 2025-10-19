const std = @import("std");
const net = std.net;
const json = std.json;
const WorldManager = @import("WorldManager.zig");
const Player = @import("Player.zig");
const network = @import("network.zig");

const MAX_CLIENTS = 8;

const ClientConnection = struct {
    stream: net.Stream,
    player_id: u32,
};

pub const GameServer = struct {
    allocator: std.mem.Allocator,
    listener: net.StreamServer,
    clients: std.ArrayList(ClientConnection),
    next_player_id: u32 = 1, // Start at 1, 0 is the host

    pub fn init(allocator: std.mem.Allocator) !GameServer {
        const address = try net.Address.parseIp("0.0.0.0", 42069);
        var listener = try net.StreamServer.init(.{ .reuse_address = true });
        try listener.listen(address);
        try listener.setBlocking(false);

        std.debug.print("✅ Server listening on 0.0.0.0:42069\n", .{});

        return .{
            .allocator = allocator,
            .listener = listener,
            .clients = try std.ArrayList(ClientConnection).initCapacity(allocator, MAX_CLIENTS),
            .next_player_id = 1,
        };
    }

    pub fn deinit(self: *GameServer) void {
        for (self.clients.items) |client| {
            client.stream.close();
        }
        self.clients.deinit();
        self.listener.deinit();
        std.debug.print("Server shut down.\n", .{});
    }

    // Accept new connections and add them to the world
    pub fn acceptConnections(self: *GameServer, world: *WorldManager.WorldManager) void {
        if (self.listener.accept()) |conn| {
            std.debug.print("Accepted connection from {any}\n", .{conn.address});

            // Create a new player for this client
            const player_id = self.next_player_id;
            self.next_player_id += 1;

            const new_player = world.addPlayer(player_id, 'A' + @as(u8, @intCast(player_id))) catch |err| {
                std.debug.print("Failed to add player: {any}\n", .{err});
                conn.stream.close();
                return;
            };
            new_player.entity.x = 5; // Spawn position
            new_player.entity.y = 5;

            self.clients.append(.{ .stream = conn.stream, .player_id = player_id }) catch |err| {
                std.debug.print("Failed to add client: {any}\n", .{err});
                conn.stream.close();
                _ = world.removePlayer(player_id);
            };
        } else |err| {
            if (err != error.WouldBlock) {
                std.debug.print("Accept error: {any}\n", .{err});
            }
        }
    }

    // Process packets from all clients and broadcast the new state
    pub fn update(self: *GameServer, world: *WorldManager.WorldManager) !void {
        // 1. Read input from clients
        var i: usize = 0;
        while (i < self.clients.items.len) {
            const client = &self.clients.items[i];
            var read_buffer: [1024]u8 = undefined;

            const bytes_read = client.stream.read(&read_buffer) catch |err| {
                if (err == error.WouldBlock) {
                    i += 1;
                    continue;
                }
                std.debug.print("Client {d} disconnected (read error).\n", .{client.player_id});
                _ = world.removePlayer(client.player_id);
                _ = self.clients.swapRemove(i);
                continue;
            };

            if (bytes_read == 0) {
                std.debug.print("Client {d} disconnected.\n", .{client.player_id});
                _ = world.removePlayer(client.player_id);
                _ = self.clients.swapRemove(i);
                continue;
            }

            // In a real game, you'd have a buffer per client to handle partial packets.
            // For this simple case, we assume one packet per read.
            var fbs = std.io.fixedBufferStream(read_buffer[0..bytes_read]);
            const parsed_input = json.parseFromStream(network.PlayerInputPacket, self.allocator, fbs, .{}) catch {
                i += 1;
                continue;
            };
            defer parsed_input.deinit();

            if (world.players.getPtr(client.player_id)) |player| {
                const action = Player.InputAction.fromKey(parsed_input.value.key);
                world.handlePlayerAction(player, action);
            }
            i += 1;
        }

        // 2. Collect game state
        var player_states = try std.ArrayList(network.PlayerState).initCapacity(self.allocator, world.players.count());
        defer player_states.deinit();

        var iter = world.players.iterator();
        while (iter.next()) |entry| {
            try player_states.append(.{
                .id = entry.key_ptr.*,
                .x = entry.value_ptr.entity.x,
                .y = entry.value_ptr.entity.y,
                .ch = entry.value_ptr.entity.ch,
            });
        }

        // 3. Serialize and broadcast to all clients
        var send_buffer = std.ArrayList(u8).init(self.allocator);
        defer send_buffer.deinit();
        const packet = network.GameStatePacket{ .players = player_states.items };
        try json.stringify(packet, .{}, send_buffer.writer());
        try send_buffer.append('\n'); 

        for (self.clients.items) |client| {
            _ = client.stream.write(send_buffer.items) catch |err| {
                std.debug.print("Write error to client {d}: {any}\n", .{ client.player_id, err });
            };
        }
    }
};

