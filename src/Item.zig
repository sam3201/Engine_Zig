// src/Item.zig
const std = @import("std");

pub const Item = struct {
    id: i32,
    name: []const u8,
    quantity: i32,

    pub fn init(id: i32, name: []const u8, quantity: i32) Item {
        return .{
            .id = id,
            .name = name,
            .quantity = quantity,
        };
    }
};

