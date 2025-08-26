// src/Chunk.zig  (only the new/changed parts)

const std = @import("std");
const Item = @import("Item.zig").Item;
const eng = @import("Engine.zig");

// ... keep your existing declarations above ...

pub const WorldItem = struct {
    item: Item,
    x: i32,
    y: i32,
    ch: u8 = '!', // render as '!' for now
    color: eng.Color = .{ .r = 255, .g = 255, .b = 0 },
};

pub const Chunk = struct {
    // existing fields...
    // e.g. coord, difficulty_level, tiles, biome, etc.
    // add:
    items: std.ArrayList(WorldItem),

    pub fn init(
        coord: ChunkCoord,
        difficulty_level: i32,
        allocator: std.mem.Allocator,
    ) !Chunk {
        var items = std.ArrayList(WorldItem).init(allocator);

        var self = Chunk{
            .coord = coord,
            .difficulty_level = difficulty_level,
            .items = items,
            // ... initialize your other existing fields ...
        };

        // Optional: spawn one test item per chunk (near chunk origin)
        try self.spawnTestItems();

        return self;
    }

    pub fn deinit(self: *Chunk) void {
        self.items.deinit();
        // deinit other dynamic fields if you have any
    }

    fn spawnTestItems(self: *Chunk) !void {
        // place a potion near the chunk origin (0,0 local -> world = chunk*SIZE + local)
        const potion = Item.init(1, "Potion", 1);
        try self.items.append(.{ .item = potion, .x = self.coord.x * CHUNK_SIZE, .y = self.coord.y * CHUNK_SIZE });
    }

    pub fn addWorldItem(self: *Chunk, wi: WorldItem) !void {
        try self.items.append(wi);
    }

    /// Returns index of the first item at (world_x, world_y) or null if none
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
};

