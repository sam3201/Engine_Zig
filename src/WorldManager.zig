const std = @import("std");
const eng = @import("Engine.zig");
const Player = @import("Player.zig");
const Chunk = @import("Chunk.zig");

pub const WorldManager = struct {
    allocator: std.mem.Allocator,
    canvas: *eng.Canvas,
    player: Player.Player,
    chunks: std.HashMap(Chunk.ChunkCoord, Chunk.Chunk, ChunkContext, std.hash_map.default_max_load_percentage),
    loaded_radius: i32 = 2, // Load chunks within this radius of player
    canvas_width: i32,
    canvas_height: i32,
    camera_x: i32 = 0,
    camera_y: i32 = 0,

    const ChunkContext = struct {
        pub fn hash(self: @This(), coord: Chunk.ChunkCoord) u64 {
            _ = self;
            return coord.hash();
        }

        pub fn eql(self: @This(), a: Chunk.ChunkCoord, b: Chunk.ChunkCoord) bool {
            _ = self;
            return a.equals(b);
        }
    };

    pub fn init(allocator: std.mem.Allocator, canvas: *eng.Canvas, player: Player.Player) !WorldManager {
        var world = WorldManager{
            .allocator = allocator,
            .canvas = canvas,
            .player = player,
            .chunks = std.HashMap(Chunk.ChunkCoord, Chunk.Chunk, ChunkContext, std.hash_map.default_max_load_percentage).init(allocator),
            .canvas_width = @intCast(canvas.width),
            .canvas_height = @intCast(canvas.height),
        };

        // Generate initial chunks around player
        try world.updateChunks();

        return world;
    }

    pub fn deinit(self: *WorldManager) void {
        self.chunks.deinit();
        self.player.deinit();
    }

    pub fn getPlayerChunkCoord(self: WorldManager) Chunk.ChunkCoord {
        const pos = self.player.getPosition();
        return Chunk.ChunkCoord{
            .x = @divFloor(pos.x, Chunk.CHUNK_SIZE),
            .y = @divFloor(pos.y, Chunk.CHUNK_SIZE),
        };
    }

    pub fn worldToChunkCoord(world_x: i32, world_y: i32) Chunk.ChunkCoord {
        return Chunk.ChunkCoord{
            .x = @divFloor(world_x, Chunk.CHUNK_SIZE),
            .y = @divFloor(world_y, Chunk.CHUNK_SIZE),
        };
    }

    pub fn worldToLocalCoord(world_x: i32, world_y: i32) struct { x: i32, y: i32 } {
        return .{
            .x = @mod(world_x, Chunk.CHUNK_SIZE),
            .y = @mod(world_y, Chunk.CHUNK_SIZE),
        };
    }

    pub fn updateChunks(self: *WorldManager) !void {
        const player_chunk = self.getPlayerChunkCoord();

        // Generate chunks around player
        var y: i32 = player_chunk.y - self.loaded_radius;
        while (y <= player_chunk.y + self.loaded_radius) : (y += 1) {
            var x: i32 = player_chunk.x - self.loaded_radius;
            while (x <= player_chunk.x + self.loaded_radius) : (x += 1) {
                const coord = Chunk.ChunkCoord{ .x = x, .y = y };

                if (!self.chunks.contains(coord)) {
                    const chunk = Chunk.Chunk.init(coord, self.player.getLevel());
                    try self.chunks.put(coord, chunk);
                }
            }
        }

        // Remove chunks that are too far away (optional optimization)
        self.unloadDistantChunks(player_chunk);
    }

    fn unloadDistantChunks(self: *WorldManager, player_chunk: Chunk.ChunkCoord) void {
        const unload_radius = self.loaded_radius + 2;

        var iterator = self.chunks.iterator();
        var coords_to_remove = std.ArrayList(Chunk.ChunkCoord).init(self.allocator);
        defer coords_to_remove.deinit();

        while (iterator.next()) |entry| {
            const coord = entry.key_ptr.*;
            const distance = @abs(coord.x - player_chunk.x) + @abs(coord.y - player_chunk.y);

            if (distance > unload_radius) {
                coords_to_remove.append(coord) catch continue;
            }
        }

        for (coords_to_remove.items) |coord| {
            _ = self.chunks.remove(coord);
        }
    }

    pub fn getTileAtWorld(self: WorldManager, world_x: i32, world_y: i32) Chunk.TileType {
        const chunk_coord = worldToChunkCoord(world_x, world_y);
        const local_coord = worldToLocalCoord(world_x, world_y);

        if (self.chunks.get(chunk_coord)) |chunk| {
            return chunk.getTile(local_coord.x, local_coord.y);
        }

        return .Stone; // Default for unloaded chunks
    }

    pub fn isWalkableAtWorld(self: WorldManager, world_x: i32, world_y: i32) bool {
        const tile = self.getTileAtWorld(world_x, world_y);
        return tile.isWalkable();
    }

    pub fn processPlayerInput(self: *WorldManager, input: u8) !void {
        const action = self.player.processInput(input);
        try self.handlePlayerAction(action);
    }

    fn handlePlayerAction(self: *WorldManager, action: Player.InputAction) !void {
        const old_pos = self.player.getPosition();

        switch (action) {
            .UP => self.tryMovePlayer(0, -1),
            .DOWN => self.tryMovePlayer(0, 1),
            .LEFT => self.tryMovePlayer(-1, 0),
            .RIGHT => self.tryMovePlayer(1, 0),
            .INTERACT => self.playerInteract(),
            .ATTACK => self.playerAttack(),
            .USEITEM => self.playerUseItem(),
            .DROPITEM => {},
            .OPENINVENTORY => self.playerOpenInventory(),
            .None => {},
        }

        const new_pos = self.player.getPosition();

        // Update chunks if player moved to a new chunk
        if (@divFloor(old_pos.x, Chunk.CHUNK_SIZE) != @divFloor(new_pos.x, Chunk.CHUNK_SIZE) or
            @divFloor(old_pos.y, Chunk.CHUNK_SIZE) != @divFloor(new_pos.y, Chunk.CHUNK_SIZE))
        {
            try self.updateChunks();
        }
    }

    fn tryMovePlayer(self: *WorldManager, dx: i32, dy: i32) void {
        const pos = self.player.getPosition();
        const new_x = pos.x + dx;
        const new_y = pos.y + dy;

        if (self.isWalkableAtWorld(new_x, new_y)) {
            self.player.move(dx, dy);

            // Update camera to follow player
            self.updateCamera();
        }
    }

    fn updateCamera(self: *WorldManager) void {
        const pos = self.player.getPosition();

        // Center camera on player
        self.camera_x = pos.x - @divTrunc(self.canvas_width, 2);
        self.camera_y = pos.y - @divTrunc(self.canvas_height, 2);
    }

    fn playerInteract(self: *WorldManager) void {
        // TODO: Implement interaction logic
        _ = self;
    }

    fn playerAttack(self: *WorldManager) void {
        // TODO: Implement attack logic
        _ = self;
    }

    fn playerUseItem(self: *WorldManager) void {
        // TODO: Implement item usage
        _ = self;
    }

    fn playerOpenInventory(self: *WorldManager) void {
        // TODO: Implement inventory system
        _ = self;
    }

    pub fn draw(self: *WorldManager) void {
        // Clear canvas
        for (0..@intCast(self.canvas_height)) |screen_y| {
            for (0..@intCast(self.canvas_width)) |screen_x| {
                const world_x = self.camera_x + @as(i32, @intCast(screen_x));
                const world_y = self.camera_y + @as(i32, @intCast(screen_y));

                const tile = self.getTileAtWorld(world_x, world_y);

                self.canvas.put(@intCast(screen_x), @intCast(screen_y), tile.getChar());
                self.canvas.fillColor(@intCast(screen_x), @intCast(screen_y), tile.getColor());
            }
        }

        // Draw player
        const pos = self.player.getPosition();
        const screen_x = pos.x - self.camera_x;
        const screen_y = pos.y - self.camera_y;

        // Only draw player if on screen
        if (screen_x >= 0 and screen_x < self.canvas_width and screen_y >= 0 and screen_y < self.canvas_height) {
            self.canvas.put(screen_x, screen_y, self.player.entity.ch);
            self.canvas.fillColor(screen_x, screen_y, self.player.entity.color);
        }

        // Draw HUD
        self.drawHUD();
    }

    fn drawHUD(self: *WorldManager) void {
        // Draw player info
        const pos = self.player.getPosition();
        const chunk_coord = self.getPlayerChunkCoord();

        const info_text = std.fmt.allocPrint(self.allocator, " HP: {}/{} | Pos: ({},{}) | Chunk: ({},{}) | Chunks: {} ", .{ self.player.health, self.player.max_health, pos.x, pos.y, chunk_coord.x, chunk_coord.y, self.chunks.count() }) catch return;
        defer self.allocator.free(info_text);

        const quarter_health = @divTrunc(self.player.max_health, 4);
        const half_health = @divTrunc(self.player.max_health, 2);

        const health_color = if (self.player.health < quarter_health)
            eng.Color{ .r = 255, .g = 0, .b = 0 } // Red when low health
        else if (self.player.health < half_health)
            eng.Color{ .r = 255, .g = 255, .b = 0 } // Yellow when medium health
        else
            eng.Color{ .r = 0, .g = 255, .b = 0 }; // Green when high health

        // Draw HUD background
        for (0..info_text.len) |i| {
            if (i < self.canvas.width) {
                self.canvas.put(@intCast(i), 0, ' ');
                self.canvas.fillColor(@intCast(i), 0, eng.Color{ .r = 0, .g = 0, .b = 64 });
            }
        }

        // Draw HUD text
        for (info_text, 0..) |ch, i| {
            if (i < self.canvas.width) {
                self.canvas.put(@intCast(i), 0, ch);
                self.canvas.fillColor(@intCast(i), 0, health_color);
            }
        }

        // Draw current biome info
        const current_chunk_coord = self.getPlayerChunkCoord();
        if (self.chunks.get(current_chunk_coord)) |chunk| {
            const biome_text = std.fmt.allocPrint(self.allocator, " Biome: {} | Difficulty: {} ", .{ chunk.biome, chunk.difficulty_level }) catch return;
            defer self.allocator.free(biome_text);

            const biome_color = switch (chunk.biome) {
                .Plains => eng.Color{ .r = 100, .g = 255, .b = 100 },
                .Forest => eng.Color{ .r = 0, .g = 150, .b = 0 },
                .Mountains => eng.Color{ .r = 150, .g = 150, .b = 150 },
                .Desert => eng.Color{ .r = 255, .g = 200, .b = 100 },
                .Tundra => eng.Color{ .r = 200, .g = 200, .b = 255 },
                .Volcanic => eng.Color{ .r = 255, .g = 100, .b = 100 },
            };

            for (biome_text, 0..) |ch, i| {
                const screen_y = 1;
                if (i < self.canvas.width and screen_y < self.canvas.height) {
                    self.canvas.put(@intCast(i), screen_y, ch);
                    self.canvas.fillColor(@intCast(i), screen_y, biome_color);
                }
            }
        }
    }
};
