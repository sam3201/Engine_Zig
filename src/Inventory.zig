// Inventory.zig
const std = @import("std");

pub const ItemType = enum {
    Weapon,
    Armor,
    Consumable,
    Ammo,
    Other,
};

pub const WeaponVariant = enum(u8) { Pistol = 'P', Shotgun = 'S' };
pub const ArmorVariant = enum(u8) { Light = 'L', Medium = 'M', Heavy = 'H' };
pub const ConsumableVariant = enum(u8) { Potion = 'o', Food = 'f' };
pub const AmmoVariant = enum(u8) { AmmoPistol = 'p', AmmoShotgun = 's' };
pub const OtherVariant = enum(u8) { Unknown = '?' };

pub const Item = struct {
    item_type: ItemType,
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

    pub fn initConsumable(variant: ConsumableVariant, quantity: u32, allocator: std.mem.Allocator) Item {
        return Item.init(.Consumable, @intCast(variant), quantity, allocator);
    }

    pub fn initWeapon(variant: WeaponVariant, quantity: u32, allocator: std.mem.Allocator) Item {
        return Item.init(.Weapon, @intCast(u8, variant), quantity, allocator);
    }

    pub fn initArmor(variant: ArmorVariant, quantity: u32, allocator: std.mem.Allocator) Item {
        return Item.init(.Armor, @intCast(u8, variant), quantity, allocator);
    }

    pub fn initAmmo(variant: AmmoVariant, quantity: u32, allocator: std.mem.Allocator) Item {
        return Item.init(.Ammo, @intCast(u8, variant), quantity, allocator);
    }

    pub fn initOther(variant: OtherVariant, quantity: u32, allocator: std.mem.Allocator) Item {
        return Item.init(.Other, @intCast(u8, variant), quantity, allocator);
    }

    pub fn displayName(self: Item) []const u8 {
        switch (self.item_type) {
            .Consumable => switch (@as(ConsumableVariant, self.variant_char)) {
                .Potion => "Potion",
                .Food => "Food",
            },
            .Weapon => switch (@as(WeaponVariant, self.variant_char)) {
                .Pistol => "Pistol",
                .Shotgun => "Shotgun",
            },
            .Armor => switch (@as(ArmorVariant, self.variant_char)) {
                .Light => "Light Armor",
                .Medium => "Medium Armor",
                .Heavy => "Heavy Armor",
            },
            .Ammo => switch (@as(AmmoVariant, self.variant_char)) {
                .AmmoPistol => "Pistol Ammo",
                .AmmoShotgun => "Shotgun Ammo",
            },
            .Other => "Other",
        }
    }

    pub fn deinit(self: *Item) void {
        // nothing heap-allocated inside Item currently; kept for API symmetry
        _ = self;
    }

    pub fn copy(self: Item) Item {
        return Item{
            .item_type = self.item_type,
            .variant_char = self.variant_char,
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
        // ArrayList.deinit requires allocator in 0.15
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
