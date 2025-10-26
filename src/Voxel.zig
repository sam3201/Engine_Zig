// src/Voxel.zig

const std = @import("std");
const Engine3D = @import("Engine3D.zig");
const Chunk = @import("Chunk.zig");

pub const VoxelType = enum {
    Air,
    Dirt,
    Grass,
    Stone,
    Sand,
    Water,
    Wood,
    Leaves,
    Snow,
    
    pub fn fromTileType(tile: Chunk.TileType) VoxelType {
        return switch (tile) {
            .Empty => .Air,
            .Grass => .Grass,
            .Stone, .Wall => .Stone,
            .Water => .Water,
            .Tree => .Wood,
            .Desert => .Sand,
            .Snow => .Snow,
            .Mountain => .Stone,
            .Lava => .Stone, // For now
        };
    }
    
    pub fn getColor(self: VoxelType) Engine3D.Color3D {
        return switch (self) {
            .Air => Engine3D.Color3D.init(0, 0, 0),
            .Dirt => Engine3D.Color3D.init(139, 90, 43),
            .Grass => Engine3D.Color3D.init(34, 139, 34),
            .Stone => Engine3D.Color3D.init(128, 128, 128),
            .Sand => Engine3D.Color3D.init(194, 178, 128),
            .Water => Engine3D.Color3D.init(30, 144, 255),
            .Wood => Engine3D.Color3D.init(101, 67, 33),
            .Leaves => Engine3D.Color3D.init(0, 100, 0),
            .Snow => Engine3D.Color3D.init(255, 250, 250),
        };
    }
    
    pub fn isSolid(self: VoxelType) bool {
        return self != .Air and self != .Water;
    }
};

pub const Voxel = struct {
    voxel_type: VoxelType,
    
    pub fn init(voxel_type: VoxelType) Voxel {
        return .{ .voxel_type = voxel_type };
    }
};

// 3D coordinate
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

pub const VoxelWorld = struct {
    allocator: std.mem.Allocator,
    voxels: std.AutoHashMap(VoxelCoord, Voxel),
    
    pub const VoxelCoord = struct {
        x: i32,
        y: i32,
        z: i32,
        
        pub fn hash(self: VoxelCoord) u64 {
            const x_hash: u64 = @bitCast(@as(i64, self.x));
            const y_hash: u64 = @bitCast(@as(i64, self.y));
            const z_hash: u64 = @bitCast(@as(i64, self.z));
            return x_hash ^ (y_hash << 1) ^ (z_hash << 2);
        }
        
        pub fn eql(self: VoxelCoord, other: VoxelCoord) bool {
            return self.x == other.x and self.y == other.y and self.z == other.z;
        }
    };
    
    const VoxelContext = struct {
        pub fn hash(self: @This(), coord: VoxelCoord) u64 {
            _ = self;
            return coord.hash();
        }
        
        pub fn eql(self: @This(), a: VoxelCoord, b: VoxelCoord) bool {
            _ = self;
            return a.eql(b);
        }
    };
    
    pub fn init(allocator: std.mem.Allocator) !VoxelWorld {
        return VoxelWorld{
            .allocator = allocator,
            .voxels = std.AutoHashMap(VoxelCoord, Voxel).init(allocator),
        };
    }
    
    pub fn deinit(self: *VoxelWorld) void {
        self.voxels.deinit();
    }
    
    pub fn setVoxel(self: *VoxelWorld, x: i32, y: i32, z: i32, voxel: Voxel) !void {
        try self.voxels.put(.{ .x = x, .y = y, .z = z }, voxel);
    }
    
    pub fn getVoxel(self: *VoxelWorld, x: i32, y: i32, z: i32) ?Voxel {
        return self.voxels.get(.{ .x = x, .y = y, .z = z });
    }
    
    pub fn removeVoxel(self: *VoxelWorld, x: i32, y: i32, z: i32) void {
        _ = self.voxels.remove(.{ .x = x, .y = y, .z = z });
    }
};
