// src/Inventory.zig
const std = @import("std");

pub const ItemType = enum {
    Weapon,
    Armor,
    Consumable,
    Ammo,
    Other,
};

pub const ConsumableVariant = enum(u8) {
    Potion = 'o',
    Food = 'f',
};

pub const Item = struct {
    item_type: ItemType,
    /// store variant as the underlying integer (u8) so Item is trivially copyable
    variant_char: u8,
    quantity: u32,
    allocator: std.mem.Allocator,

    pub fn init(item_type: ItemType, variant_char: u8, quantity: u32, allocator: std.mem.Allocator) Item {
        return Item{
            .item_type = item_type,
            .variant_char = variant_char,
            .quantity = quantity,
            .allocator = allocator,
        };
    }

    /// convenience constructor for consumables
    pub fn initConsumable(variant: ConsumableVariant, quantity: u32, allocator: std.mem.Allocator) Item {
        // convert enum value to its underlying integer
        const v_u8: u8 = @intFromEnum(variant);
        return Item.init(.Consumable, v_u8, quantity, allocator);
    }

    pub fn deinit(self: *Item) void {
        // currently we don't allocate per-item strings; if you add heap allocations for names,
        // free them here using self.allocator
        _ = self;
    }

    /// return printable character for this item (char used on map)
    pub fn displayChar(self: *Item) u8 {
        return switch (self.item_type) {
            .Consumable => switch (@enumFromInt(self.variant_char)) {
                .Potion => 'o',
                .Food => 'f',
            },
            else => '?',
        };
    }

    pub fn displayName(self: *Item) []const u8 {
        return switch (self.item_type) {
            .Consumable => switch (@enumFromInt(self.variant_char)) {
                .Potion => "Potion",
                .Food => "Food",
            },
            .Weapon => "Weapon",
            .Armor => "Armor",
            .Ammo => "Ammo",
            .Other => "Other",
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
        for (self.items.items) |*it| {
            it.deinit();
        }
        self.items.deinit(self.allocator);
    }

    pub fn addItem(self: *Inventory, item: Item) !void {
        for (self.items.items) |*it| {
            if (it.item_type == item.item_type and it.variant_char == item.variant_char) {
                it.quantity += item.quantity;
                return;
            }
        }
        try self.items.append(self.allocator, item);
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
