// src/Inventory.zig

const std = @import("std");

pub const Item = struct {
    id: u32,
    name: []const u8,
    quantity: u32,

    pub fn init(id: u32, name: []const u8, quantity: u32) Item {
        return Item{
            .id = id,
            .name = name,
            .quantity = quantity,
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
        // merge if same name
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
