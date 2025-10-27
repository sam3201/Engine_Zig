// src/Chunk.zig

const std = @import("std");
const Engine = @import("Engine.zig");
const Inventory = @import("Inventory.zig");
const WorldManager = @import("WorldManager.zig");

pub const CHUNK_WIDTH: usize = 150;
pub const CHUNK_HEIGHT: usize = 50;

pub const TileType = enum {
    Empty,
    Wall,
    Grass,
    Stone,
    Water,
    Tree,
    Mountain,
    Desert,
    Snow,
    Lava,

    pub fn getChar(self: TileType) u8 {
        return switch (self) {
            .Empty => '.',
            .Wall => '#',
            .Grass => ',',
            .Stone => '@',
            .Water => '~',
            .Tree => 'T',
            .Mountain => '^',
            .Desert => ':',
            .Snow => '*',
            .Lava => '=',
        };
    }

    pub fn getColor(self: TileType) Engine.Color {
        return switch (self) {
            .Empty => Engine.Color{ .r = 64, .g = 64, .b = 64 },
            .Wall => Engine.Color{ .r = 128, .g = 64, .b = 0 }, 
            .Grass => Engine.Color{ .r = 0, .g = 128, .b = 0 },
            .Stone => Engine.Color{ .r = 128, .g = 128, .b = 128 },
            .Water => Engine.Color{ .r = 0, .g = 0, .b = 255 },
            .Tree => Engine.Color{ .r = 0, .g = 100, .b = 0 },
            .Mountain => Engine.Color{ .r = 100, .g = 100, .b = 100 },
            .Desert => Engine.Color{ .r = 200, .g = 180, .b = 100 },
            .Snow => Engine.Color{ .r = 255, .g = 255, .b = 255 },
            .Lava => Engine.Color{ .r = 255, .g = 50, .b = 0 },
        };
    }

    pub fn isWalkable(self: TileType) bool {
        return switch (self) {
            .Empty, .Grass, .Desert, .Snow => true,
            .Wall, .Stone, .Water, .Tree, .Mountain, .Lava => false, 
        };
    }
};

pub const BiomeType = enum {
    Plains,
    Forest,
    Mountains,
    Desert,
    Tundra,
    Volcanic,

    pub fn getPrimaryTile(self: BiomeType) TileType {
        return switch (self) {
            .Plains => .Grass,
            .Forest => .Tree,
            .Mountains => .Mountain,
            .Desert => .Desert,
            .Tundra => .Snow,
            .Volcanic => .Lava,
        };
    }

    pub fn getSecondaryTile(self: BiomeType) TileType {
        return switch (self) {
            .Plains => .Empty,
            .Forest => .Grass,
            .Mountains => .Stone,
            .Desert => .Stone,
            .Tundra => .Stone,
            .Volcanic => .Stone,
        };
    }
};

pub const BiomeCount: u32 = 6;

pub const ChunkCoord = struct {
    x: usize,
    y: usize,

    pub fn hash(self: ChunkCoord) usize {
        const x_hash: usize @bitCast(self.x);
        const y_hash: u64 = @bitCast(@as(i64, self.y));
        return x_hash ^ (y_hash << 1);
    }

    pub fn equals(self: ChunkCoord, other: ChunkCoord) bool {
        return self.x == other.x and self.y == other.y;
    }
};

pub const WorldItem = struct {
    item: Inventory.Item,
    x: i32,
    y: i32,
    ch: u8,
    color: Engine.Color = .{ .r = 255, .g = 255, .b = 0 },

    pub fn init(allocator: std.mem.Allocator, item_type: Inventory.ItemType, variant_char: u8, quantity: i32, coord: ChunkCoord) WorldItem {
        return WorldItem{
            .item = Inventory.Item.init(item_type, variant_char, quantity, allocator),
            .x = coord.x,
            .y = coord.y,
            .ch = ' ',
        };
    }
};

pub const Chunk = struct {
    allocator: std.mem.Allocator,
    coord: ChunkCoord,
    tiles: [CHUNK_WIDTH * CHUNK_HEIGHT]TileType,
    biome: BiomeType,
    difficulty: i32,
    generated: bool = false,
    items: std.ArrayList(WorldItem),

    pub fn init(coord: ChunkCoord, biome: BiomeType, difficulty: i32, allocator: std.mem.Allocator) !Chunk {
        var self = Chunk{
            .allocator = allocator,
            .coord = coord,
            .biome = biome,
            .tiles = [_]TileType{TileType.Empty} ** (CHUNK_WIDTH * CHUNK_HEIGHT),
            .difficulty = difficulty,
            .generated = true,
            .items = undefined,
        };

        self.items = try std.ArrayList(WorldItem).initCapacity(allocator, 8);
        try self.items.ensureTotalCapacity(allocator, 8);

        var prng = std.Random.DefaultPrng.init(coord.hash());
        self.generateTerrain(prng.random());

        try self.items.append(allocator, WorldItem{
            .item = Inventory.Item.initConsumable(.Potion, 1, "Potion", allocator),
            .x = self.coord.x * CHUNK_WIDTH + 2,
            .y = self.coord.y * CHUNK_HEIGHT + 2,
            .ch = 'P',
            .color = Engine.Color{ .r = 200, .g = 0, .b = 200 },
        });

        return self;
    }

    pub fn deinit(self: *Chunk) void {
        self.items.deinit(self.allocator);
    }

    pub fn addWorldItem(self: *Chunk, wi: WorldItem) !void {
        try self.items.append(self.allocator, wi);
    }

    pub fn findItemAt(self: *Chunk, world_x: i32, world_y: i32) ?usize {
        var i: usize = 0;
        while (i < self.items.items.len) : (i += 1) {
            const it = self.items.items[i];
            if (it.x == world_x and it.y == world_y) return i;
        }
        return null;
    }

    pub fn removeItemIndex(self: *Chunk, i: usize) void {
        _ = self.items.orderedRemove(i);
    }

        pub fn generate(self: *Chunk) void {
        var rng = std.Random.DefaultPrng.init(self.coord.hash());

        // Start with mostly walkable terrain
        for (0..CHUNK_HEIGHT) |y| {
            for (0..CHUNK_WIDTH) |x| {
                const idx = y * CHUNK_WIDTH + x;
                const roll = rng.random().intRangeAtMost(u8, 0, 100);

                // Much more open - mostly walkable tiles
                self.tiles[idx] = switch (self.biome) {
                    .Plains => if (roll < 95) .Grass else if (roll < 98) .Tree else .Empty,
                    .Forest => if (roll < 80) .Grass else if (roll < 95) .Tree else .Grass,
                    .Mountains => if (roll < 90) .Empty else if (roll < 97) .Stone else .Mountain,
                    .Desert => if (roll < 95) .Desert else if (roll < 98) .Stone else .Empty,
                    .Tundra => if (roll < 92) .Snow else if (roll < 97) .Empty else .Stone,
                    .Volcanic => if (roll < 88) .Empty else if (roll < 95) .Stone else .Lava,
                };
            }
        }

        // Add very sparse features
        self.addFeatures(rng.random());
    }

    fn selectBiome(self: *Chunk, distance: i32, player_level: i32, random: std.Random) BiomeType {
        _ = self;

        if (distance < 2) {
            return .Plains;
        }

        if (player_level < 5) {
            const biomes = [_]BiomeType{ .Plains, .Forest };
            return biomes[random.intRangeAtMost(usize, 0, biomes.len - 1)];
        } else if (player_level < 15) {
            const biomes = [_]BiomeType{ .Plains, .Forest, .Mountains, .Desert };
            return biomes[random.intRangeAtMost(usize, 0, biomes.len - 1)];
        } else {
            const biomes = [_]BiomeType{ .Mountains, .Desert, .Tundra, .Volcanic };
            return biomes[random.intRangeAtMost(usize, 0, biomes.len - 1)];
        }
    }

    fn generateTerrain(self: *Chunk, random: std.Random) void {
        const primary_tile = self.biome.getPrimaryTile();
        const secondary_tile = self.biome.getSecondaryTile();

        for (0..CHUNK_WIDTH * CHUNK_HEIGHT) |i| {
            if (random.float(f32) < 0.99) {
                self.tiles[i] = primary_tile;
            } else {
                self.tiles[i] = secondary_tile;
            }
        }

                for (0..CHUNK_WIDTH * CHUNK_HEIGHT) |i| {
            if (self.tiles[i] == .Tree or self.tiles[i] == .Mountain or self.tiles[i] == .Lava) {
                self.tiles[i] = switch (self.biome) {
                    .Plains => .Grass,
                    .Forest => .Grass,
                    .Mountains => .Empty,
                    .Desert => .Desert,
                    .Tundra => .Snow,
                    .Volcanic => .Empty,
                };
            }
        }

        self.generatePaths(random);
    }

    fn generatePaths(self: *Chunk, random: std.Random) void {
        const num_paths = random.intRangeAtMost(i32, 2, 5);

        for (0..@intCast(num_paths)) |_| {
            const start_x = random.intRangeAtMost(i32, 0, CHUNK_WIDTH - 1);
            const start_y = random.intRangeAtMost(i32, 0, CHUNK_HEIGHT - 1);
            const length = random.intRangeAtMost(i32, 5, 15);

            var x = start_x;
            var y = start_y;

            for (0..@intCast(length)) |_| {
                if (x >= 0 and x < CHUNK_WIDTH and y >= 0 and y < CHUNK_HEIGHT) {
                    const idx = @as(usize, @intCast(y * CHUNK_WIDTH + x));
                    self.tiles[idx] = if (self.biome == .Desert) .Desert else .Empty;
                }

                const direction = random.intRangeAtMost(i32, 0, 3);
                switch (direction) {
                    0 => x += 1,
                    1 => x -= 1,
                    2 => y += 1,
                    3 => y -= 1,
                    else => {},
                }
            }
        }
    }

    fn addFeatures(self: *Chunk, random: std.Random) void {
        if (random.float(f32) < 0.25) {
            const lake_x = random.intRangeAtMost(i32, 5, CHUNK_WIDTH - 6);
            const lake_y = random.intRangeAtMost(i32, 5, CHUNK_HEIGHT - 6);
            const size = random.intRangeAtMost(usize, 3, 6);

            for (0..size) |dy| {
                for (0..size) |dx| {
                    const x = lake_x + @as(i32, @intCast(dx));
                    const y = lake_y + @as(i32, @intCast(dy));
                    
                    const is_edge = (dx == 0 or dx == size - 1 or dy == 0 or dy == size - 1);
                    const should_place = if (is_edge) random.float(f32) < 0.6 else true;
                    
                    if (should_place and x >= 0 and x < CHUNK_WIDTH and y >= 0 and y < CHUNK_HEIGHT) {
                        self.tiles[@intCast(y * CHUNK_WIDTH + x)] = .Water;
                    }
                }
            }
            
            if (random.float(f32) < 0.4) {
                const river_length = random.intRangeAtMost(i32, 5, 12);
                var rx = lake_x;
                var ry = lake_y;
                const direction = random.intRangeAtMost(i32, 0, 3);
                
                for (0..@intCast(river_length)) |_| {
                    if (rx >= 0 and rx < CHUNK_WIDTH and ry >= 0 and ry < CHUNK_HEIGHT) {
                        self.tiles[@intCast(ry * CHUNK_WIDTH + rx)] = .Water;
                        if (random.float(f32) < 0.5) {
                            if (direction < 2 and rx + 1 < CHUNK_WIDTH) {
                                self.tiles[@intCast(ry * CHUNK_WIDTH + rx + 1)] = .Water;
                            } else if (ry + 1 < CHUNK_HEIGHT) {
                                self.tiles[@intCast((ry + 1) * CHUNK_WIDTH + rx)] = .Water;
                            }
                        }
                    }
                    
                    switch (direction) {
                        0 => rx += 1,
                        1 => rx -= 1,
                        2 => ry += 1,
                        3 => ry -= 1,
                        else => {},
                    }
                }
            }
        }

        const obstacle_density = 0.008; 
        for (0..CHUNK_WIDTH * CHUNK_HEIGHT) |i| {
            if (random.float(f32) < obstacle_density) {
                self.tiles[i] = switch (self.biome) {
                    .Forest => .Tree,     
                    .Mountains => .Stone,  
                    .Volcanic => .Stone,   
                    .Desert => .Stone,     
                    .Tundra => .Stone,     
                    .Plains => if (random.float(f32) < 0.3) .Tree else continue,  
                };
            }
        }
    }

    pub fn getTile(self: Chunk, local_x: i32, local_y: i32) TileType {
        if (local_x < 0 or local_x >= CHUNK_WIDTH or local_y < 0 or local_y >= CHUNK_HEIGHT) {
            return .Stone; // Out of bounds
        }

        const idx = @as(usize, @intCast(local_y * CHUNK_WIDTH + local_x));
        return self.tiles[idx];
    }

    pub fn setTile(self: *Chunk, local_x: i32, local_y: i32, tile: TileType) void {
        if (local_x < 0 or local_x >= CHUNK_WIDTH or local_y < 0 or local_y >= CHUNK_HEIGHT) {
            return;
        }

        const idx = @as(usize, @intCast(local_y * CHUNK_WIDTH + local_x));
        self.tiles[idx] = tile;
    }
    pub fn save(self: *Chunk, allocator: std.mem.Allocator, dir: []const u8) !void {
        const filename = try std.fmt.allocPrint(allocator, "{s}/chunk_{d}_{d}.bin", .{ dir, self.coord.x, self.coord.y });
        defer allocator.free(filename);

        var file = try std.fs.cwd().createFile(filename, .{ .truncate = true });
        defer file.close();

        try file.writeAll(std.mem.sliceAsBytes(&self.tiles));
    }

    pub fn load(coord: ChunkCoord, allocator: std.mem.Allocator, dir: []const u8) !?Chunk {
        const filename = try std.fmt.allocPrint(allocator, "{s}/chunk_{d}_{d}.bin", .{ dir, coord.x, coord.y });
        defer allocator.free(filename);

        var file = std.fs.cwd().openFile(filename, .{}) catch return null;
        defer file.close();

        var tiles: [CHUNK_WIDTH * CHUNK_HEIGHT]TileType = undefined;
        _ = try file.readAll(std.mem.sliceAsBytes(&tiles));

        return Chunk{
            .coord = coord,
            .tiles = tiles,
            .biome = .Plains, // TODO: read biome from file too
            .difficulty = 1,
            .items = std.ArrayListUnmanaged(WorldItem){},
            .generated = true,
        };
    }
};
