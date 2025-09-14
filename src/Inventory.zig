// src/Inventory.zig

const std = @import("std");

pub const ItemType = enum {
    const Weapon = enum(u8) {
        Sword = 's',
        Axe = 'a',
        Pickaxe = 'p',
    };
    const Armor = enum(u8) {
        Leather = 'l',
        Chain = 'c',
        Iron = 'i',
    };
    const Consumable = enum(u8) {
        Potion = 'p',
        Food = 'f',
    };
};
 
pub const Item = struct {
    type: ItemType, 
    char: u8,
    quantity: u32,
    allocator: std.mem.Allocator,

    pub fn init(item_type: ItemType, quantity: u32, allocator: std.mem.Allocator) Item {
        return Item{
            switch (item_type) {
                .Weapon => |weapon| return Item{ .type = item_type, .char = weapon, .quantity = quantity, .allocator = allocator },
                .Armor => |armor| return Item{ .type = item_type, .char = armor, .quantity = quantity, .allocator = allocator },
                .Consumable => |consumable| return Item{ .type = item_type, .char = consumable, .quantity = quantity, .allocator = allocator },
            }
        };
    }

    pub fn deinit(self: *Item) void {
        self.allocator.free(self.name);
    }

    pub fn copy(self: Item) Item {
        return Item{
            .type = self.type,
            .quantity = self.quantity,
            .allocator = self.allocator,
        };
    }
};

pub const Inventory = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Item),

    pub fn init(allocator: std.mem.Allocator) !Inventory {
        return Inventory{
            .allocator = allocator,
            .items = try std.ArrayList(Item).initCapacity(allocator, 8),
        };
    }

    pub fn deinit(self: *Inventory) void {
        self.items.deinit();
    }

    pub fn addItem(self: *Inventory, item: Item) !void {
        for (self.items.items) |*it| {
            if (std.mem.eql(u8, it.name, item.name)) {
                it.quantity += item.quantity;
                return;
            }
        }
        try self.items.append(item);
    }

    pub fn removeItem(self: *Inventory, name: []const u8, amount: u32) void {
        var i: usize = 0;
        while (i < self.items.items.len) : (i += 1) {
            if (std.mem.eql(u8, self.items.items[i].name, name)) {
                if (self.items.items[i].quantity > amount) {
                    self.items.items[i].quantity -= amount;
                } else {
                    _ = self.items.swapRemove(i);
                }
                return;
            }
        }
    }

    pub fn getItem(self: *Inventory, idx: usize) ?Item {
        if (idx < self.items.items.len) return self.items.items[idx];
        return null;
    }

    pub fn len(self: *Inventory) usize {
        return self.items.items.len;
    }
};
