const std = @import("std");
const eng = @import("Engine.zig");

pub const RenderableType = enum {
    PLAYER,
    ENEMY,
    PROJECTILE,
    AI,
    NN,

    pub fn fromId(id: u32) RenderableType {
        return @enumFromInt(id);
    }

    pub fn toId(self: RenderableType) u32 {
        return @intFromEnum(self);
    }
};

pub const Entity = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 1,
    height: i32 = 1,
    id: u32 = 0,
    ch: u8 = ' ',
    color: eng.Color = eng.Color{ .r = 0, .g = 0, .b = 0 },

    pub fn init(x: i32, y: i32, w: i32, h: i32, id: u32, ch: u8, color: eng.Color) Entity {
        return .{ .x = x, .y = y, .width = w, .height = h, .id = id, .ch = ch, .color = color };
    }

    pub fn deinit(self: *Entity) void {
        _ = self;
    }

    pub fn update(self: *Entity, dx: i32, dy: i32) void {
        self.x += dx;
        self.y += dy;
    }
};
