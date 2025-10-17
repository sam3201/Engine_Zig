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

pub const ArmorVariant = enum(u8) {
    Light = 'l',
    Medium = 'm',
    Heavy = 'h',
};

pub const AmmoVariant = enum(u8) {
    Arrow = 'a',
    Bullet = 'b',
};

pub const WeaponVariant = enum(u8) {
    Pistol = 's',
    Dagger = 'd',
};

pub const Item = struct {
    item_type: ItemType,
    name: []const u8,
    variant_char: u8,
    quantity: u32,
    allocator: std.mem.Allocator,

    pub fn init(item_type: ItemType, name: []const u8, variant_char: u8, quantity: u32, allocator: std.mem.Allocator) Item {
        return Item{
            .item_type = item_type,
            .name = name,
            .variant_char = variant_char,
            .quantity = quantity,
            .allocator = allocator,
        };
    }

    pub fn initConsumable(variant: ConsumableVariant, quantity: u32, name: []const u8, allocator: std.mem.Allocator) Item {
        return Item.init(.Consumable, name, @intFromEnum(variant), quantity, allocator);
    }

    pub fn initWeapon(variant: WeaponVariant, quantity: u32, name: []const u8, allocator: std.mem.Allocator) Item {
        return Item.init(.Weapon, name, @intFromEnum(variant), quantity, allocator);
    }

    pub fn initArmor(variant: ArmorVariant, quantity: u32, name: []const u8, allocator: std.mem.Allocator) Item {
        return Item.init(.Armor, name, @intFromEnum(variant), quantity, allocator);
    }

    pub fn initAmmo(variant: AmmoVariant, quantity: u32, name: []const u8, allocator: std.mem.Allocator) Item {
        return Item.init(.Ammo, name, @intFromEnum(variant), quantity, allocator);
    }

    pub fn deinit(self: *Item) void {
        // If you later allocate per-item memory, free it here using self.allocator
        _ = self;
    }

    // Accept const pointer so callers with `*const Item` work
    pub fn displayChar(self: *const Item) u8 {
        return switch (self.item_type) {
            .Consumable => {
                const v: ConsumableVariant = @enumFromInt(self.variant_char);
                switch (v) {
                    .Potion => 'o',
                    .Food => 'f',
                }
            },
            .Weapon, .Armor, .Ammo, .Other => self.variant_char,
        };
    }

    pub fn displayName(self: *const Item) []const u8 {
        return switch (self.item_type) {
            .Consumable => {
                const v: ConsumableVariant = @enumFromInt(self.variant_char);
                return switch (v) {
                    .Potion => "Potion",
                    .Food => "Food",
                };
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
    Selected_Slot: usize = 0,
    items: std.ArrayList(Item),

    pub fn init(allocator: std.mem.Allocator) !Inventory {
        return Inventory{
            .allocator = allocator,
            .items = try std.ArrayList(Item).initCapacity(allocator, 8),
            .Selected_Slot = 0,
        };
    }

    pub fn deinit(self: *Inventory) void {
        // call deinit on each item if necessary
        var i: usize = 0;
        while (i < self.items.items.len) : (i += 1) {
            self.items.items[i].deinit();
        }
        self.items.deinit(self.allocator);
    }

    pub fn addItem(self: *Inventory, item: Item) !void {
        // merge into existing stack if same type+variant
        var i: usize = 0;
        while (i < self.items.items.len) : (i += 1) {
            if (self.items.items[i].item_type == item.item_type and self.items.items[i].variant_char == item.variant_char) {
                self.items.items[i].quantity += item.quantity;
                return;
            }
        }
        try self.items.append(self.allocator, item);
    }

    pub fn findByName(self: *Inventory, name: []const u8) ?*Item {
        var i: usize = 0;
        while (i < self.items.items.len) : (i += 1) {
            if (std.mem.eql(u8, self.items.items[i].name, name)) return &self.items.items[i];
        }
        return null;
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
