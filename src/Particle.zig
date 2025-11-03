// src/Particle.zig

const std = @import("std");
const Engine3D = @import("Engine3D.zig");
const Chunk = @import("Chunk.zig");

var MAX_PARTICLES: [Chunk.CHUNK_WIDTH * Chunk.CHUNK_HEIGHT]Particle = undefined; 

pub const Particle = struct {
    x: f32,
    y: f32,
    z: f32,
    color: Engine3D.Color3D,
    tile_type: Chunk.TileType,
    
    pub fn init(x: f32, y: f32, z: f32, tile_type: Chunk.TileType) Particle {
        return .{
            .x = x,
            .y = y,
            .z = z,
            .color = getColorForTile(tile_type, z),
            .tile_type = tile_type,
        };
    }
    
    fn getColorForTile(tile_type: Chunk.TileType, height: f32) Engine3D.Color3D {
    return switch (tile_type) {
        .Empty => if (height < 0.1)
            Engine3D.Color3D.init(40, 40, 40)  // Dark ground
        else
            Engine3D.Color3D.init(64, 64, 64),
        .Grass => if (height < 0.1) 
            Engine3D.Color3D.init(34, 139, 34)  // Forest green ground
        else if (height > 0.5) 
            Engine3D.Color3D.init(50, 200, 50)  // Bright grass on top
        else 
            Engine3D.Color3D.init(101, 67, 33),  // Dirt in middle
        .Stone => if (height < 0.1)
            Engine3D.Color3D.init(80, 80, 80)  // Dark stone ground
        else
            Engine3D.Color3D.init(128, 128, 128),
        .Water => Engine3D.Color3D.init(30, 100, 200),
        .Tree => if (height > 3.0)
            Engine3D.Color3D.init(0, 150, 0)     // Leaves
        else if (height < 0.5)
            Engine3D.Color3D.init(139, 90, 43)   // Trunk base
        else
            Engine3D.Color3D.init(101, 67, 33),  // Trunk middle
        .Mountain => if (height < 0.1)
            Engine3D.Color3D.init(70, 70, 70)   // Mountain base
        else
            Engine3D.Color3D.init(100, 100, 100),
        .Desert => if (height < 0.1)
            Engine3D.Color3D.init(194, 178, 128)  // Sand ground
        else
            Engine3D.Color3D.init(220, 180, 100),
        .Snow => if (height < 0.1)
            Engine3D.Color3D.init(240, 248, 255)  // Snow ground
        else
            Engine3D.Color3D.init(255, 255, 255),
        .Lava => if (height < 0.1)
            Engine3D.Color3D.init(139, 0, 0)      // Dark lava ground
        else
            Engine3D.Color3D.init(255, 100, 0),
        .Wall => if (height < 0.1)
            Engine3D.Color3D.init(101, 67, 33)    // Brown ground
        else
            Engine3D.Color3D.init(139, 90, 43),
    };
    }
};

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,
    
    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }
    
    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return Vec3.init(self.x + other.x, self.y + other.y, self.z + other.z);
    }
    
    pub fn sub(self: Vec3, other: Vec3) Vec3 {
        return Vec3.init(self.x - other.x, self.y - other.y, self.z - other.z);
    }
    
    pub fn scale(self: Vec3, s: f32) Vec3 {
        return Vec3.init(self.x * s, self.y * s, self.z * s);
    }
    
    pub fn length(self: Vec3) f32 {
        return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }
    
    pub fn normalize(self: Vec3) Vec3 {
        const len = self.length();
        if (len == 0) return Vec3.init(0, 0, 0);
        return self.scale(1.0 / len);
    }
    
    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }
    
    pub fn cross(self: Vec3, other: Vec3) Vec3 {
        return Vec3.init(
            self.y * other.z - self.z * other.y,
            self.z * other.x - self.x * other.z,
            self.x * other.y - self.y * other.x,
        );
    }
};

pub const ParticleQuality = enum {
    Low,      // 1 particle per tile (1x1x1)
    Medium,   // 4 particles per tile (2x2x2)
    High,     // 16 particles per tile (4x4x4)
    Ultra,    // 64 particles per tile (8x8x8)
    
    pub fn getSubdivisions(self: ParticleQuality) usize {
        return switch (self) {
            .Low => 1,
            .Medium => 4,
            .High => 16,
            .Ultra => 64,
        };
    }
    
    pub fn getParticlesPerTile(self: ParticleQuality) usize {
        const sub = self.getSubdivisions();
        return sub * sub * sub;
    }
};

pub const ParticleField = struct {
    allocator: std.mem.Allocator,
    particles: std.ArrayList(Particle),
    quality: ParticleQuality,
    
    pub fn init(allocator: std.mem.Allocator, quality: ParticleQuality) !ParticleField {
        return ParticleField{
            .allocator = allocator,
            .particles = try std.ArrayList(Particle).initCapacity(allocator, quality.getParticlesPerTile()), 
            .quality = quality,
        };
    }
    
    pub fn deinit(self: *ParticleField) void {
        self.particles.deinit(self.allocator);
    }
    
    pub fn clear(self: *ParticleField) void {
        self.particles.clearRetainingCapacity();
    }
    
    pub fn addParticle(self: *ParticleField, allocator: std.mem.Allocator, particle: Particle) !void {
        try self.particles.append(allocator, particle);
    }
    
    pub fn getHeightForTile(tile_type: Chunk.TileType) f32 {
        return switch (tile_type) {
            .Empty => 0.0,
            .Grass => 0.2,
            .Desert => 0.3,
            .Snow => 0.4,
            .Stone => 1.0,
            .Water => 0.0,
            .Tree => 4.0,
            .Mountain => 6.0,
            .Wall => 2.0,
            .Lava => 0.2,
        };
    }
};
