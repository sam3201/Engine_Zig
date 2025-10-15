// src/Player.zig
const std = @import("std");
const Inventory = @import("Inventory.zig");
const Engine = @import("Engine.zig");
const Entity = @import("Entity.zig").Entity;

pub const InputAction = enum {
    None,
    MoveUp,
    MoveDown,
    MoveLeft,
    MoveRight,
    Interact,
    Attack,
    UseItem,
    OpenInventory,

    pub fn fromKey(key: u8) InputAction {
        return switch (key) {
            'w', 'W' => .MoveUp,
            's', 'S' => .MoveDown,
            'a', 'A' => .MoveLeft,
            'd', 'D' => .MoveRight,
            'e', 'E' => .Interact,
            ' ' => .Attack,
            'i', 'I' => .OpenInventory,
            else => .None,
        };
    }
};

pub const Player = struct {
    allocator: std.mem.Allocator,
    entity: Entity,
    health: i32,
    max_health: i32,
    level: i32,
    inventory: Inventory.Inventory,

    pub fn init(
        allocator: std.mem.Allocator,
        entity: Entity,
        health: i32,
        max_health: i32,
        level: i32,
        inv: Inventory.Inventory,
    ) Player {
        return Player{
            .allocator = allocator,
            .entity = entity,
            .health = health,
            .max_health = max_health,
            .level = level,
            .inventory = inv,
        };
    }

    pub fn createWASDPlayer(allocator: std.mem.Allocator, start_x: i32, start_y: i32) !Player {
        const inv = try Inventory.Inventory.init(allocator);

        const p = Player{
            .allocator = allocator,
            .entity = Entity{ .ch = '@', .color = Engine.Color{ .r = 255, .g = 255, .b = 255 }, .x = start_x, .y = start_y },
            .health = 100,
            .max_health = 100,
            .level = 1,
            .inventory = inv,
        };
        return p;
    }

    pub fn createArrowPlayer(allocator: std.mem.Allocator, start_x: i32, start_y: i32) !Player {
        var inv = try Inventory.Inventory.init(allocator);

        const arrow_item = Inventory.Item.init(.Ammo, '>', 10, allocator);
        try inv.addItem(arrow_item);

        const p = Player{
            .allocator = allocator,
            .entity = Entity{ .ch = 'A', .color = Engine.Color{ .r = 200, .g = 200, .b = 0 }, .x = start_x, .y = start_y },
            .health = 80,
            .max_health = 80,
            .level = 1,
            .inventory = inv,
        };
        return p;
    }

    pub fn deinit(self: *Player) void {
        self.inventory.deinit();
    }

    pub fn getPosition(self: *const Player) struct { x: i32, y: i32 } {
        return .{ .x = self.entity.x, .y = self.entity.y };
    }

    pub fn processInput(self: *Player, input: u8) u8 {
        _ = self;
        return input;
    }

    pub fn addItem(self: *Player, item: Inventory.Item) !void {
        try self.inventory.addItem(item);
    }

    pub fn removeItemByName(self: *Player, name: []const u8, amount: u32) void {
        if (self.inventory.findByName(name)) |it| {
            const item_ptr = it;
            const it_type = item_ptr.*.item_type;
            const it_variant = item_ptr.*.variant_char;
            self.inventory.removeItem(it_type, it_variant, amount);
        }
    }

    pub fn getItemByIndex(self: *Player, idx: usize) ?Inventory.Item {
        return self.inventory.getItem(idx);
    }

    pub fn saveToFile(self: *Player, path: []const u8) !void {
        const fs = std.fs.cwd();
        var file = try fs.createFile(path, .{ .truncate = true });
        defer file.close();

        var write_buf: [1024]u8 = undefined;
        var w = file.writer(write_buf[0..]);
        try w.writeAll("player\n");
        try w.print("health: {d}\n", .{self.health});
        try w.print("max_health: {d}\n", .{self.max_health});
        try w.print("level: {d}\n", .{self.level});
        try w.print("x: {d}\n", .{self.entity.x});
        try w.print("y: {d}\n", .{self.entity.y});
        try w.print("inventory:\n");
        for (self.inventory.items.items) |it| {
            try it.saveToFile(w);
        }
    }
};
