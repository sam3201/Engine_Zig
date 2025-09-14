// src/Inventory.zig

const std = @import("std");

pub const ItemType = enum {
    None,
    Weapon,
    Armor,
    Consumable,
};

pub const Item = struct {
    item_type: ItemType,
    variant_char: u8,
    quantity: u32,

    pub fn init(item_type: ItemType, variant_char: u8, quantity: u32) Item {
        return Item{
            .item_type = item_type,
            .variant_char = variant_char,
            .quantity = quantity,
        };
    }

    pub fn deinit(self: *Item) void {
        // nothing heap-allocated inside Item anymore
        _ = self;
    }

    pub fn copy(self: Item) Item {
        return Item{
            .item_type = self.item_type,
            .variant_char = self.variant_char,
            .quantity = self.quantity,
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
        // no per-item heap allocations to free (if you later store names or dup strings,
        // free them here)
        self.items.deinit();
    }

    pub fn addItem(self: *Inventory, item: Item) !void {
        // combine by type+variant_char
        for (self.items.items) |*it| {
            if (it.item_type == item.item_type and it.variant_char == item.variant_char) {
                it.quantity += item.quantity;
                return;
            }
        }
        try self.items.append(item);
    }

    pub fn removeItem(self: *Inventory, item_type: ItemType, variant_char: u8, amount: u32) void {
        var i: usize = 0;
        while (i < self.items.items.len) : (i += 1) {
            if (self.items.items[i].item_type == item_type and self.items.items[i].variant_char == variant_char) {
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
