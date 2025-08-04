const std = @import("std");
const eng = @import("Engine.zig");

pub const CHUNK_SIZE: i32 = 32;

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

    pub fn getColor(self: TileType) eng.Color {
        return switch (self) {
            .Empty => eng.Color{ .r = 64, .g = 64, .b = 64 },
            .Grass => eng.Color{ .r = 0, .g = 128, .b = 0 },
            .Stone => eng.Color{ .r = 128, .g = 128, .b = 128 },
            .Water => eng.Color{ .r = 0, .g = 0, .b = 255 },
            .Tree => eng.Color{ .r = 0, .g = 100, .b = 0 },
            .Mountain => eng.Color{ .r = 100, .g = 100, .b = 100 },
            .Desert => eng.Color{ .r = 200, .g = 180, .b = 100 },
            .Snow => eng.Color{ .r = 255, .g = 255, .b = 255 },
            .Lava => eng.Color{ .r = 255, .g = 50, .b = 0 },
        };
    }

    pub fn isWalkable(self: TileType) bool {
        return switch (self) {
            .Empty, .Grass, .Desert, .Snow => true,
            .Stone, .Water, .Tree, .Mountain, .Lava => false,
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

pub const ChunkCoord = struct {
    x: i32,
    y: i32,

    pub fn hash(self: ChunkCoord) u64 {
        const x_hash: u64 = @bitCast(@as(i64, self.x));
        const y_hash: u64 = @bitCast(@as(i64, self.y));
        return x_hash ^ (y_hash << 1);
    }

    pub fn equals(self: ChunkCoord, other: ChunkCoord) bool {
        return self.x == other.x and self.y == other.y;
    }
};

pub const Chunk = struct {
    coord: ChunkCoord,
    tiles: [CHUNK_SIZE * CHUNK_SIZE]TileType,
    biome: BiomeType,
    difficulty_level: i32,
    generated: bool = false,

    pub fn init(coord: ChunkCoord, difficulty_level: i32) Chunk {
        var tiles: [CHUNK_SIZE * CHUNK_SIZE]TileType = undefined;

        for (0..CHUNK_SIZE) |y| {
            for (0..CHUNK_SIZE) |x| {
                const idx = y * CHUNK_SIZE + x;
                if (x == 0 or y == 0 or x == CHUNK_SIZE - 1 or y == CHUNK_SIZE - 1) {
                    tiles[idx] = .Wall;
                } else {
                    tiles[idx] = .Empty;
                }
            }
        }

        return Chunk{
            .coord = coord,
            .tiles = tiles,
            .biome = .Plains,
            .difficulty_level = difficulty_level,
        };
    }

    pub fn generate(self: *Chunk, player_level: i32) void {
        const seed = self.coord.hash();
        var rng = std.Random.DefaultPrng.init(seed);
        const random = rng.random();

        const distance_from_origin: i32 = @intCast(@abs(self.coord.x) + @abs(self.coord.y));
        self.biome = self.selectBiome(distance_from_origin, player_level, random);
        self.difficulty_level = player_level + @divTrunc(distance_from_origin, 3);

        self.generateTerrain(random);

        self.addFeatures(random);

        self.generated = true;
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

        for (0..CHUNK_SIZE * CHUNK_SIZE) |i| {
            if (random.float(f32) < 0.7) {
                self.tiles[i] = primary_tile;
            } else {
                self.tiles[i] = secondary_tile;
            }
        }

        self.generatePaths(random);
    }

    fn generatePaths(self: *Chunk, random: std.Random) void {
        const num_paths = random.intRangeAtMost(i32, 2, 5);

        for (0..@intCast(num_paths)) |_| {
            const start_x = random.intRangeAtMost(i32, 0, CHUNK_SIZE - 1);
            const start_y = random.intRangeAtMost(i32, 0, CHUNK_SIZE - 1);
            const length = random.intRangeAtMost(i32, 5, 15);

            var x = start_x;
            var y = start_y;

            for (0..@intCast(length)) |_| {
                if (x >= 0 and x < CHUNK_SIZE and y >= 0 and y < CHUNK_SIZE) {
                    const idx = @as(usize, @intCast(y * CHUNK_SIZE + x));
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
        if (random.float(f32) < 0.3) {
            const water_x = random.intRangeAtMost(i32, 2, CHUNK_SIZE - 3);
            const water_y = random.intRangeAtMost(i32, 2, CHUNK_SIZE - 3);
            const water_size = random.intRangeAtMost(i32, 2, 4);

            for (0..@intCast(water_size)) |dy| {
                for (0..@intCast(water_size)) |dx| {
                    const x = water_x + @as(i32, @intCast(dx));
                    const y = water_y + @as(i32, @intCast(dy));
                    if (x < CHUNK_SIZE and y < CHUNK_SIZE) {
                        const idx = @as(usize, @intCast(y * CHUNK_SIZE + x));
                        self.tiles[idx] = .Water;
                    }
                }
            }
        }

        const obstacle_density = @min(0.4, @as(f32, @floatFromInt(self.difficulty_level)) * 0.02);
        for (0..CHUNK_SIZE * CHUNK_SIZE) |i| {
            if (random.float(f32) < obstacle_density) {
                self.tiles[i] = .Stone;
            }
        }
    }

    pub fn getTile(self: Chunk, local_x: i32, local_y: i32) TileType {
        if (local_x < 0 or local_x >= CHUNK_SIZE or local_y < 0 or local_y >= CHUNK_SIZE) {
            return .Stone; // Out of bounds
        }

        const idx = @as(usize, @intCast(local_y * CHUNK_SIZE + local_x));
        return self.tiles[idx];
    }

    pub fn setTile(self: *Chunk, local_x: i32, local_y: i32, tile: TileType) void {
        if (local_x < 0 or local_x >= CHUNK_SIZE or local_y < 0 or local_y >= CHUNK_SIZE) {
            return;
        }

        const idx = @as(usize, @intCast(local_y * CHUNK_SIZE + local_x));
        self.tiles[idx] = tile;
    }
};
