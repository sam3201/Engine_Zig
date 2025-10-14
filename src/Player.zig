// src/Player.zig
const std = @import("std");
const Inventory = @import("Inventory.zig");
const Engine = @import("Engine.zig");
const Entity = @import("Entity.zig");

pub const Player = struct {
    entity: Entity,
    health: i32,
    max_health: i32,
    level: i32,
    inventory: Inventory.Inventory,

    pub fn init(entity: Entity, health: i32, max_health: i32, level: i32, inv: Inventory.Inventory) Player {
        return Player{
            .entity = entity,
            .health = health,
            .max_health = max_health,
            .level = level,
            .inventory = inv,
        };
    }
    pub fn createWASDPlayer(allocator: std.mem.Allocator, start_x: i32, start_y: i32) !Player {
        var inv = try Inventory.Inventory.init(allocator);

        const p = Player{
            .allocator = allocator,
            .entity = Player.Entity{ .ch = '@', .color = Engine.Color{ .r = 255, .g = 255, .b = 255 }, .x = start_x, .y = start_y },
            .health = 100,
            .max_health = 100,
            .level = 1,
            .inventory = inv,
        };
        return p;
    }

    pub fn createArrowPlayer(allocator: std.mem.Allocator, start_x: i32, start_y: i32) !Player {
        var inv = try Inventory.Inventory.init(allocator);

        // give a starter arrow item for example
        const arrow_item = Inventory.Item.init(.Ammo, "Arrow", '>', 10, allocator);
        try inv.addItem(arrow_item);

        const p = Player{
            .allocator = allocator,
            .entity = Player.Entity{ .ch = 'A', .color = Engine.Color{ .r = 200, .g = 200, .b = 0 }, .x = start_x, .y = start_y },
            .health = 80,
            .max_health = 80,
            .level = 1,
            .inventory = inv,
        };
        return p;
    }

    pub fn deinit(self: *Player) void {
        // deinit inventory contents and inventory itself
        self.inventory.deinit();
    }

    pub fn getPosition(self: *const Player) struct { x: i32, y: i32 } {
        return .{ .x = self.entity.x, .y = self.entity.y };
    }

    /// process a single input byte and return an action code (you can keep your old InputAction enum elsewhere)
    pub fn processInput(self: *Player, input: u8) void {
        // This stub mirrors whatever your project expects — adapt as needed.
        // Return something that WorldManager.handlePlayerAction understands.
        // For now, return the byte so existing code can parse it.
        return input;
    }

    pub fn addItem(self: *Player, item: Inventory.Item) !void {
        try self.inventory.addItem(item);
    }

    /// Remove item by name (string) and amount. This uses Inventory.findByName to locate the item,
    /// then calls Inventory.removeItem with the right type/variant parameters.
    pub fn removeItemByName(self: *Player, name: []const u8, amount: u32) void {
        if (self.inventory.findByName(name)) |it| {
            const item_ptr = it; // type: *Inventory.Item
            const it_type = item_ptr.*.item_type;
            const it_variant = item_ptr.*.variant_char;
            self.inventory.removeItem(it_type, it_variant, amount);
        }
    }

    /// If your previous code used an index-based getItem, keep this helper:
    pub fn getItemByIndex(self: *Player, idx: usize) ?Inventory.Item {
        return self.inventory.getItem(idx);
    }

    /// Example: save player to a file. Demonstrates changed File.writer API that requires buffer.
    pub fn saveToFile(self: *Player, path: []const u8) !void {
        const fs = std.fs.cwd();
        var file = try fs.createFile(path, .{ .truncate = true });
        defer file.close();

        var write_buf: [1024]u8 = undefined;
        var w = file.writer(&write_buf);

        // Write a simple line
        _ = w.writeAll("player\n") catch {};
        // flush if writer type provides flush; if not, writeAll is sufficient
    }
};
