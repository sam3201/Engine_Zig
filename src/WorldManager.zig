// src/WorldManager.zig

const std = @import("std");
const Particle = @import("Particle.zig");
const Engine = @import("Engine.zig");
const Engine3D = @import("Engine3D.zig");
const Player = @import("Player.zig");
const Chunk = @import("Chunk.zig");
const Inventory = @import("Inventory.zig");

const MAX_PLAYERS = 64;
pub const CHUNK_WIDTH: usize = 150;
pub const CHUNK_HEIGHT: usize = 50;

pub const WorldManager = struct {
    allocator: std.mem.Allocator,
    canvas: *Engine.Canvas,
    player: Player.Player,
    Players: std.ArrayList(Player.Player), 
    chunks: std.HashMap(Chunk.ChunkCoord, Chunk.Chunk, ChunkContext, std.hash_map.default_max_load_percentage),
    loaded_radius: usize = 2,
    canvas_width: usize,
    canvas_height: usize,
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

    pub fn init(coord: Chunk.ChunkCoord, difficulty: i32, allocator: std.mem.Allocator, canvas: *Engine.Canvas, player: Player.Player) !WorldManager {
        var world = WorldManager{
            .allocator = allocator,
            .canvas = canvas,
            .player = player,
            .Players = try std.ArrayList(Player.Player).initCapacity(allocator, MAX_PLAYERS),
            .chunks = std.HashMap(Chunk.ChunkCoord, Chunk.Chunk, ChunkContext, std.hash_map.default_max_load_percentage).init(allocator),
            .canvas_width = @intCast(canvas.width),
            .canvas_height = @intCast(canvas.height),
        };

        const start_biome = randomBiome();
        const chunk = try Chunk.Chunk.init(coord, start_biome, difficulty, allocator);
        try world.chunks.put(.{ .x = 0, .y = 0 }, chunk);

        try world.updateChunks();
        world.updateCamera();

        return world;
    }

    pub fn deinit(self: *WorldManager) void {
        var it = self.chunks.valueIterator();
        while (it.next()) |c| {
            c.deinit();
        }
        self.chunks.deinit();
        for (self.Players.items) |*p| {
            p.deinit();
        }
        self.Players.deinit(self.allocator);
        
    }

    pub fn addPlayer(self: *WorldManager, player: Player.Player) !void {
        try self.Players.append(player);
    }

    pub fn getPlayerChunkCoord(self: WorldManager) Chunk.ChunkCoord {
        const pos = self.player.getPosition();
        return Chunk.ChunkCoord{
            .x = @divFloor(pos.x, @as(i32, CHUNK_WIDTH)),
            .y = @divFloor(pos.y, @as(i32, CHUNK_HEIGHT)),
        };
    }

    pub fn worldToChunkCoord(world_x: i32, world_y: i32) Chunk.ChunkCoord {
        return Chunk.ChunkCoord{
            .x = @divFloor(world_x, @as(i32, CHUNK_WIDTH)),
            .y = @divFloor(world_y, @as(i32, CHUNK_HEIGHT)), 
        };
    }

    pub fn worldToLocalCoord(world_x: i32, world_y: i32) struct { x: i32, y: i32 } {
        return .{
            .x = @mod(world_x, @as(i32, CHUNK_WIDTH)), 
            .y = @mod(world_y, @as(i32, CHUNK_HEIGHT)), 
        };
    }

    fn biomeForCoord(coord: Chunk.ChunkCoord, seed: u64) Chunk.BiomeType {
        var rng = std.Random.DefaultPrng.init(coord.hash() ^ seed);
        const r: u32 = rng.random().intRangeLessThan(u32, 0, Chunk.BiomeCount);
        return @enumFromInt(r);
    }

    pub fn updateChunks(self: *WorldManager) !void {
        const player_chunk = self.getPlayerChunkCoord();

        var y: i32 = player_chunk.y - @as(i32, self.loaded_radius);
        while (y <= player_chunk.y + @as(i32, self.loaded_radius)) : (y += 1) {
            var x: i32 = player_chunk.x - @as(i32, self.loaded_radius);
            while (x <= player_chunk.x + self.loaded_radius) : (x += 1) {
                const coord = Chunk.ChunkCoord{ .x = x, .y = y };
                if (!self.chunks.contains(coord)) {
                    const player_level: u64 = @intCast(self.player.level);
                    const biome = biomeForCoord(coord, player_level);
                    const chunk = try Chunk.Chunk.init(coord, biome, self.player.level, self.allocator);
                    try self.chunks.put(coord, chunk);
                }
            }
        }
        try self.unloadDistantChunks(player_chunk);
    }

    fn unloadDistantChunks(self: *WorldManager, player_chunk: Chunk.ChunkCoord) !void {
        const unload_radius = self.loaded_radius + 2;

        var iterator = self.chunks.iterator();
        var coords_to_remove = try std.ArrayList(Chunk.ChunkCoord).initCapacity(self.allocator, 8);
        defer coords_to_remove.deinit(self.allocator);

        while (iterator.next()) |entry| {
            const coord = entry.key_ptr.*;
            const distance = @abs(coord.x - player_chunk.x) + @abs(coord.y - player_chunk.y);

            if (distance > unload_radius) {
                coords_to_remove.append(self.allocator, coord) catch continue;
            }
        }

        for (coords_to_remove.items) |coord| {
            _ = self.chunks.remove(coord);
        }
    }

    pub fn getBiome(self: WorldManager) Chunk.BiomeType {
        const coord = self.getPlayerChunkCoord();
        return self.chunks.get(coord).?.biome;
    }

    pub fn getTileAtWorld(self: WorldManager, world_x: i32, world_y: i32) Chunk.TileType {
        const chunk_coord = worldToChunkCoord(world_x, world_y);
        const local_coord = worldToLocalCoord(world_x, world_y);

        if (self.chunks.get(chunk_coord)) |chunk| {
            return chunk.getTile(local_coord.x, local_coord.y);
        }

        return .Stone;
    }

    pub fn isWalkableAtWorld(self: WorldManager, world_x: i32, world_y: i32) bool {
        const tile = self.getTileAtWorld(world_x, world_y);
        return tile.isWalkable();
    }

    pub fn processPlayerInput(self: *WorldManager, input: u8) !void {
        const action = self.player.processInput(input);
        try self.handlePlayerAction(action);
    }

    pub fn serializeState(self: *WorldManager, buffer: []u8) !usize {
        var i: usize = 0;
        for (self.Players.items) |p| {
            if (i + 2 >= buffer.len) break;
            buffer[i] = @intCast(@mod(p.entity.x, 255));
            buffer[i + 1] = @intCast(@mod(p.entity.y, 255));
            i += 2;
        }
        return i;
    }

    pub fn deserializeState(self: *WorldManager, data: []const u8) void {
        self.Players.clearRetainingCapacity();
        var i: usize = 0;
        while (i + 2 <= data.len) : (i += 2) {
            const x = @as(i32, data[i]);
            const y = @as(i32, data[i + 1]);
            const entity = Player.Entity.init(x, y, 1, 1, 0, "@", Engine.Color{ .r = 255, .g = 0, .b = 0 });
            const player = Player.Player.init(entity, 100, 100, 0, undefined);
            _ = self.Players.append(player) catch {};
        }
    }

    pub fn handlePlayerAction(self: *WorldManager, action: Player.InputAction) !void {
        const old_pos = self.player.getPosition();

        switch (action) {
            .UP => self.MovePlayer(0, -1),
            .DOWN => self.MovePlayer(0, 1),
            .LEFT => self.MovePlayer(-1, 0),
            .RIGHT => self.MovePlayer(1, 0),
            .INTERACT => self.playerInteract(),
            .ATTACK => self.playerAttack(),
            .USEITEM => self.playerUseItem(),
            .DROPITEM => self.playerDropItem(),
            .OPENINVENTORY => self.playerOpenInventory(),
            .SLOT0 => self.playerSelectInventorySlot(0),
            .SLOT1 => self.playerSelectInventorySlot(1),
            .SLOT2 => self.playerSelectInventorySlot(2),
            .SLOT3 => self.playerSelectInventorySlot(3),
            .SLOT4 => self.playerSelectInventorySlot(4),
            .SLOT5 => self.playerSelectInventorySlot(5),
            .SLOT6 => self.playerSelectInventorySlot(6),
            .SLOT7 => self.playerSelectInventorySlot(7),
            .SLOT8 => self.playerSelectInventorySlot(8),
            .SLOT9 => self.playerSelectInventorySlot(9),
            .NONE => {},
        }

        const new_pos = self.player.getPosition();
        if (@divFloor(old_pos.x, CHUNK_WIDTH) != @divFloor(new_pos.x, CHUNK_WIDTH) or
            @divFloor(old_pos.y, CHUNK_HEIGHT) != @divFloor(new_pos.y, CHUNK_HEIGHT))
         {
             try self.updateChunks();
         }

        self.updateCamera();
    }

    pub fn updateCamera(self: *WorldManager) void {
        const pos = self.player.getPosition();

        self.camera_x = pos.x - @divTrunc(self.canvas_width, 2);
        self.camera_y = pos.y - @divTrunc(self.canvas_height, 2);
    }

    fn MovePlayer(self: *WorldManager, dx: i32, dy: i32) void {
        const pos = self.player.getPosition();
        const new_x = pos.x + dx;
        const new_y = pos.y + dy;

        if (self.isWalkableAtWorld(new_x, new_y)) {
            self.player.move(dx, dy);

            self.updateCamera();
        }
    }


    fn playerInteract(self: *WorldManager) void {
        const pos = self.player.getPosition();
        const chunk_coord = worldToChunkCoord(pos.x, pos.y);

        if (self.chunks.getPtr(chunk_coord)) |chunk| {
            if (chunk.findItemAt(pos.x, pos.y)) |idx| {
                const wi = chunk.items.items[idx];
                const item = wi.item;
                _ = self.player.addItem(item) catch return;
                chunk.removeItemIndex(idx);

            }
        }
    }

    fn playerDropItem(self: *WorldManager) void {
        if (self.player.inventory.len() == 0) return;

        const pos = self.player.getPosition();
        const chunk_coord = worldToChunkCoord(pos.x, pos.y);

        if (self.chunks.getPtr(chunk_coord)) |chunk| {
            const item = self.player.inventory.getItem(0).?;
            const drop = Chunk.WorldItem{
                .item = item,
                .x = pos.x,
                .y = pos.y,
                .ch = item.displayName()[0],
            };

            if (chunk.findItemAt(pos.x, pos.y) == null) {
                chunk.addWorldItem(drop) catch return;
                self.player.removeItemByName(item.name, 1);
            }
        }
    }

    fn playerAttack(self: *WorldManager) void {
        // TODO
        _ = self;
    }

    fn playerUseItem(self: *WorldManager) void {
        // TODO:
        _ = self;
    }

    fn playerSelectInventorySlot(self: *WorldManager, slot: u8) void {
        if (self.player.inventory.getItem(slot))  |_| {
            self.player.inventory.Selected_Slot = slot;
        }
        
    }

    fn playerOpenInventory(self: *WorldManager) void {
        // TODO:
        _ = self;
    }

    pub fn draw(self: *WorldManager) void {
        for (0..@intCast(self.canvas_height)) |screen_y| {
            for (0..@intCast(self.canvas_width)) |screen_x| {
                const world_x = self.camera_x + @as(i32, @intCast(screen_x));
                const world_y = self.camera_y + @as(i32, @intCast(screen_y));
                const tile = self.getTileAtWorld(world_x, world_y);

                self.canvas.put(@intCast(screen_x), @intCast(screen_y), tile.getChar());
                self.canvas.fillColor(@intCast(screen_x), @intCast(screen_y), tile.getColor());
            }
        }

        var it = self.chunks.valueIterator();
        while (it.next()) |chunk| {
            for (chunk.items.items) |wi| {
                const sx = wi.x - self.camera_x;
                const sy = wi.y - self.camera_y;
                if (sx >= 0 and sx < self.canvas_width and sy >= 0 and sy < self.canvas_height) {
                    self.canvas.put(sx, sy, wi.ch);
                    self.canvas.fillColor(sx, sy, wi.color);
                }
            }
        }

        const pos = self.player.getPosition();
        const screen_x = pos.x - self.camera_x;
        const screen_y = pos.y - self.camera_y;
        if (screen_x >= 0 and screen_x < self.canvas_width and screen_y >= 0 and screen_y < self.canvas_height) {
            self.canvas.put(screen_x, screen_y, self.player.entity.ch);
            self.canvas.fillColor(screen_x, screen_y, self.player.entity.color);
        }

        self.drawHUD();
        self.drawHotbar();
    }

    fn drawHotbar(self: *WorldManager) void {
        const canvas = self.canvas;
        const bottom_y: i32 = self.canvas_height - 1;
        const slot_count: usize = 10; 
        const slot_width: i32 = 4; 

        var x_offset: i32 = 2;
        var i: usize = 0;
        while (i < slot_count) : (i += 1) {
            const slot_x = x_offset;
            const selected = (self.player.inventory.Selected_Slot) == i;

            const maybe_item = self.player.inventory.getItem(i);
            if (maybe_item) |it| {
                const slot_num: u8 = @intCast(i + 1);
                canvas.put(slot_x, bottom_y, '0' + slot_num);
                canvas.fillColor(slot_x, bottom_y, Engine.Color{ .r = 150, .g = 150, .b = 150 });
                
                canvas.put(slot_x + 1, bottom_y, ':');
                canvas.fillColor(slot_x + 1, bottom_y, Engine.Color{ .r = 100, .g = 100, .b = 100 });
                
                canvas.put(slot_x + 2, bottom_y, it.variant_char);
                canvas.fillColor(slot_x + 2, bottom_y, if (selected) 
                    Engine.Color{ .r = 255, .g = 255, .b = 100 }
                else 
                    Engine.Color{ .r = 180, .g = 180, .b = 80 });
            }

            x_offset += slot_width;
        }
    }

    fn drawHUD(self: *WorldManager) void {
        const pos = self.player.getPosition();
        const chunk_coord = self.getPlayerChunkCoord();

        const info_text = std.fmt.allocPrint(self.allocator, " HP: {}/{} | Pos: ({},{}) | Chunk: ({},{}) | Chunks: {} ", .{ self.player.health, self.player.max_health, pos.x, pos.y, chunk_coord.x, chunk_coord.y, self.chunks.count() }) catch return;
        defer self.allocator.free(info_text);

        const quarter_health = @divTrunc(self.player.max_health, 4);
        const half_health = @divTrunc(self.player.max_health, 2);

        const health_color = if (self.player.health < quarter_health)
            Engine.Color{ .r = 255, .g = 0, .b = 0 }
        else if (self.player.health < half_health)
            Engine.Color{ .r = 255, .g = 255, .b = 0 }
        else
            Engine.Color{ .r = 0, .g = 255, .b = 0 };

        const inv_str = std.fmt.allocPrint(self.allocator, "Inventory: ", .{}) catch return;
        defer self.allocator.free(inv_str);

        for (inv_str, 0..) |ch, i| {
            const y: i32 = 2;
            if (i < self.canvas.width) {
                self.canvas.put(@intCast(i), y, ch);
                self.canvas.fillColor(@intCast(i), y, Engine.Color{ .r = 200, .g = 200, .b = 200 });
            }
        }

        var offset: usize = inv_str.len;
        for (self.player.inventory.items.items) |it| {
            const entry = std.fmt.allocPrint(self.allocator, "{s}({d}) ", .{ it.displayName(), it.quantity }) catch continue;
            defer self.allocator.free(entry);

            for (entry, 0..) |ch, j| {
                const y: i32 = 2;
                const x: usize = offset + j;
                if (x < self.canvas.width) {
                    self.canvas.put(@intCast(x), y, ch);
                    self.canvas.fillColor(@intCast(x), y, Engine.Color{ .r = 180, .g = 180, .b = 0 });
                }
            }
            offset += entry.len;
        }

        for (0..info_text.len) |i| {
            if (i < self.canvas.width) {
                self.canvas.put(@intCast(i), 0, ' ');
                self.canvas.fillColor(@intCast(i), 0, Engine.Color{ .r = 0, .g = 0, .b = 64 });
            }
        }

        for (info_text, 0..) |ch, i| {
            if (i < self.canvas.width) {
                self.canvas.put(@intCast(i), 0, ch);
                self.canvas.fillColor(@intCast(i), 0, health_color);
            }
        }

        const current_chunk_coord = self.getPlayerChunkCoord();
        if (self.chunks.get(current_chunk_coord)) |chunk| {
            const biome_text = std.fmt.allocPrint(self.allocator, " Biome: {} | Difficulty: {} ", .{ chunk.biome, chunk.difficulty }) catch return;
            defer self.allocator.free(biome_text);

            const biome_color = switch (chunk.biome) {
                .Plains => Engine.Color{ .r = 100, .g = 255, .b = 100 },
                .Forest => Engine.Color{ .r = 0, .g = 150, .b = 0 },
                .Mountains => Engine.Color{ .r = 150, .g = 150, .b = 150 },
                .Desert => Engine.Color{ .r = 255, .g = 200, .b = 100 },
                .Tundra => Engine.Color{ .r = 200, .g = 200, .b = 255 },
                .Volcanic => Engine.Color{ .r = 255, .g = 100, .b = 100 },
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

const TileInfo = struct {
    h: i32,
    ch: u8,
    color: Engine3D.Color3D,
};

fn getTileInfo(tile: Chunk.TileType) TileInfo {
    return switch (tile) {
        .Empty => .{ .h = 0, .ch = '.', .color = Engine3D.Color3D.init(64, 64, 64) },
        .Grass => .{ .h = 1, .ch = ',', .color = Engine3D.Color3D.init(20, 120, 20) },
        .Tree => .{ .h = 3, .ch = 'T', .color = Engine3D.Color3D.init(0, 100, 0) },
        .Stone => .{ .h = 2, .ch = '@', .color = Engine3D.Color3D.init(120, 120, 120) },
        .Water => .{ .h = 0, .ch = '~', .color = Engine3D.Color3D.init(0, 0, 160) },
        .Mountain => .{ .h = 4, .ch = '^', .color = Engine3D.Color3D.init(100, 100, 100) },
        .Desert => .{ .h = 0, .ch = ':', .color = Engine3D.Color3D.init(200, 180, 100) },
        .Snow => .{ .h = 1, .ch = '*', .color = Engine3D.Color3D.init(240, 240, 240) },
        .Lava => .{ .h = 1, .ch = '=', .color = Engine3D.Color3D.init(255, 80, 0) },
        .Wall => .{ .h = 2, .ch = '#', .color = Engine3D.Color3D.init(100, 60, 0) },
    };
}


pub fn projectTo3D(self: *WorldManager, canvas3D: *Engine3D.Canvas3D, cam3d: *Engine3D.Camera3D) void {
    const max_depth: i32 = 18;
    const height_scale: i32 = 1;

    const screen_w: i32 = @intCast(canvas3D.width);
    const screen_h: i32 = @intCast(canvas3D.height);

    canvas3D.clear(' ', Engine3D.Color3D.init(0, 0, 0));

    var sx_i: usize = 0;
    while (sx_i < screen_w) : (sx_i += 1) {
        const sx: i32 = @intCast(sx_i);
        const world_x = cam3d.x + sx;

        var depth: i32 = 0;
        var highest_drawn_y: i32 = screen_h - 1;

        while (depth < max_depth and highest_drawn_y >= 0) : (depth += 1) {
            const world_y = cam3d.y + depth;
            const tile = self.getTileAtWorld(world_x, world_y);
            const info = getTileInfo(tile);
            const tile_h = info.h;

            const fade: f32 = if (depth < 4) 1.0 else 1.0 - ((@as(f32, @floatFromInt(depth)) / @as(f32, @floatFromInt(max_depth))) * 0.7);

            var stack_h = tile_h * height_scale;
            if (stack_h == 0) {
                stack_h = 1;
            }

            var yoff: i32 = 0;
            while (yoff < stack_h and highest_drawn_y >= 0) : (yoff += 1) {
                const sy = highest_drawn_y;
                const ch = info.ch;
                const base = info.color;

                const r: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(base.r)) * fade));
                const g: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(base.g)) * fade));
                const b: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(base.b)) * fade));

                canvas3D.put(sx, sy, ch);
                canvas3D.fillColor(sx, sy, Engine3D.Color3D.init(r, g, b));

                highest_drawn_y -= 1;
            }
        }
    }

    const pos = self.player.getPosition();
    const px = pos.x - cam3d.x;
    const py = pos.y - cam3d.y;
    if (px >= 0 and px < screen_w and py >= 0 and py < screen_h) {
        canvas3D.put(px, py, self.player.entity.ch);
        canvas3D.fillColor(px, py, Engine3D.Color3D.init(255, 255, 0));
    }
}

pub fn generateParticleField(
    self: *WorldManager,
    allocator: std.mem.Allocator,
    quality: Particle.ParticleQuality,
    render_distance: i32,
) !Particle.ParticleField {
    var field = try Particle.ParticleField.init(allocator, quality);
    
    const subdivisions = quality.getSubdivisions();
    const step: f32 = 1.0 / @as(f32, @floatFromInt(subdivisions));
    
    const pos = self.player.getPosition();
    
    var dx: i32 = -render_distance;
    while (dx <= render_distance) : (dx += 1) {
        var dy: i32 = -render_distance;
        while (dy <= render_distance) : (dy += 1) {
            const world_x = pos.x + dx;
            const world_y = pos.y + dy;
            
            const tile = self.getTileAtWorld(world_x, world_y);
            const max_height = Particle.ParticleField.getHeightForTile(tile);
            
            if (max_height <= 0.0) continue;
            
            var sx: usize = 0;
            while (sx < subdivisions) : (sx += 1) {
                var sy: usize = 0;
                while (sy < subdivisions) : (sy += 1) {
                    var sz: usize = 0;
                    while (sz < subdivisions) : (sz += 1) {
                        const particle_x = @as(f32, @floatFromInt(world_x)) + @as(f32, @floatFromInt(sx)) * step;
                        const particle_y = @as(f32, @floatFromInt(world_y)) + @as(f32, @floatFromInt(sy)) * step;
                        const particle_z = @as(f32, @floatFromInt(sz)) * step * max_height;
                        
                        if (particle_z <= max_height) {
                            try field.addParticle(self.allocator, Particle.Particle.init(
                                particle_x,
                                particle_y,
                                particle_z,
                                tile,
                            ));
                        }
                    }
                }
            }
        }
    }
    
    return field;
}

pub fn renderParticleField3D(
    self: *WorldManager,
    canvas3D: *Engine3D.Canvas3D,
    cam3d: *Engine3D.Camera3D,
    particle_field: *Particle.ParticleField,
) void {
    const screen_w: i32 = @intCast(canvas3D.width);
    const screen_h: i32 = @intCast(canvas3D.height);
    
    canvas3D.clear(' ', Engine3D.Color3D.init(135, 206, 235));
    
    const cam_pos = Particle.Vec3.init(
        @floatFromInt(self.player.getPosition().x),
        @floatFromInt(self.player.getPosition().y),
        @floatFromInt(cam3d.z),
    );
    
    const cos_yaw = @cos(cam3d.yaw);
    const sin_yaw = @sin(cam3d.yaw);
    const cos_pitch = @cos(cam3d.pitch);
    const sin_pitch = @sin(cam3d.pitch);
    
    const forward = Particle.Vec3.init(
        cos_pitch * sin_yaw,
        cos_pitch * cos_yaw,
        sin_pitch,
    ).normalize();
    
    const right = Particle.Vec3.init(-cos_yaw, sin_yaw, 0).normalize();
    const up = right.cross(forward).normalize();
    
    const depth_buffer = self.allocator.alloc(f32, @intCast(screen_w * screen_h)) catch return;
    defer self.allocator.free(depth_buffer);
    
    for (0..depth_buffer.len) |i| {
        depth_buffer[i] = std.math.inf(f32);
    }
    
    for (particle_field.particles.items) |particle| {
        const particle_pos = Particle.Vec3.init(particle.x, particle.y, particle.z);
        const relative = particle_pos.sub(cam_pos);
        
        const cam_x = relative.dot(right);
        const cam_y = relative.dot(forward);
        const cam_z = relative.dot(up);
        
        if (cam_y <= 0.1) continue;
        
        const fov_scale = @tan(cam3d.fov * 0.5 * std.math.pi / 180.0);
        const aspect = @as(f32, @floatFromInt(screen_w)) / @as(f32, @floatFromInt(screen_h));
        
        const proj_x = (cam_x / cam_y) / (aspect * fov_scale);
        const proj_z = (cam_z / cam_y) / fov_scale;
        
        const screen_x_f = (proj_x * 0.5 + 0.5) * @as(f32, @floatFromInt(screen_w));
        const screen_y_f = (0.5 - proj_z * 0.5) * @as(f32, @floatFromInt(screen_h));
        
        const screen_x: i32 = @intFromFloat(screen_x_f);
        const screen_y: i32 = @intFromFloat(screen_y_f);

        if (screen_x < 0 or screen_x >= screen_w or screen_y < 0 or screen_y >= screen_h) continue;
        
        const depth_idx: usize = @intCast(screen_y * screen_w + screen_x);
        const distance = cam_y;
        
        if (distance < depth_buffer[depth_idx]) {
            depth_buffer[depth_idx] = distance;
            
            const max_view_dist: f32 = 30.0;
            const fade = 1.0 - @min(1.0, distance / max_view_dist);
            
            const base_color = particle.color;
            const r: u8 = @intFromFloat(@as(f32, @floatFromInt(base_color.r)) * fade);
            const g: u8 = @intFromFloat(@as(f32, @floatFromInt(base_color.g)) * fade);
            const b: u8 = @intFromFloat(@as(f32, @floatFromInt(base_color.b)) * fade);
            
            const ch: u8 = if (distance < 5.0) 
                '#' 
            else if (distance < 10.0) 
                '@' 
            else if (distance < 20.0) 
                '+' 
            else 
                '.';
            
            canvas3D.put(screen_x, screen_y, ch);
            canvas3D.fillColor(screen_x, screen_y, Engine3D.Color3D.init(r, g, b));
        }
    }
    
    const center_x = @divTrunc(screen_w, 2);
    const center_y = @divTrunc(screen_h, 2);
    canvas3D.put(center_x, center_y, '+');
    canvas3D.fillColor(center_x, center_y, Engine3D.Color3D.init(255, 255, 255));
}

};

pub fn randomBiome() Chunk.BiomeType {
    const seed: u64 = @intCast(std.time.milliTimestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    const roll: u32 = prng.random().intRangeLessThan(u32, 0, Chunk.BiomeCount);
    return @enumFromInt(roll);
}

