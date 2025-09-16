// src/Inventory.zig
const std = @import("std");

pub const ItemType = enum {
    Weapon,
    Armor,
    Consumable,
    Ammo,
    Other,
};

pub const WeaponType = enum { Pistol, Shotgun };
pub const ArmorType = enum { Light, Medium, Heavy };
pub const ConsumableType = enum { Potion, Food };
pub const AmmoType = enum { Pistol, Shotgun };

pub const Item = struct {
    item_type: ItemType,
    variant: union(ItemType) {
        Weapon: WeaponType,
        Armor: ArmorType,
        Consumable: ConsumableType,
        Ammo: AmmoType,
        Other: void,
    },
    quantity: u32,

    pub fn initWeapon(weapon: WeaponType, quantity: u32) Item {
        return .{
            .item_type = .Weapon,
            .variant = .{ .Weapon = weapon },
            .quantity = quantity,
        };
    }

    pub fn initArmor(armor: ArmorType, quantity: u32) Item {
        return .{
            .item_type = .Armor,
            .variant = .{ .Armor = armor },
            .quantity = quantity,
        };
    }

    pub fn initConsumable(consumable: ConsumableType, quantity: u32) Item {
        return .{
            .item_type = .Consumable,
            .variant = .{ .Consumable = consumable },
            .quantity = quantity,
        };
    }

    pub fn initAmmo(ammo: AmmoType, quantity: u32) Item {
        return .{
            .item_type = .Ammo,
            .variant = .{ .Ammo = ammo },
            .quantity = quantity,
        };
    }

    pub fn initOther(quantity: u32) Item {
        return .{
            .item_type = .Other,
            .variant = .{ .Other = {} },
            .quantity = quantity,
        };
    }

    /// Returns a human-readable display name
    pub fn displayName(self: Item) []const u8 {
        return switch (self.item_type) {
            .Weapon => switch (self.variant.Weapon) {
                .Pistol => "Pistol",
                .Shotgun => "Shotgun",
            },
            .Armor => switch (self.variant.Armor) {
                .Light => "Light Armor",
                .Medium => "Medium Armor",
                .Heavy => "Heavy Armor",
            },
            .Consumable => switch (self.variant.Consumable) {
                .Potion => "Potion",
                .Food => "Food",
            },
            .Ammo => switch (self.variant.Ammo) {
                .Pistol => "Pistol Ammo",
                .Shotgun => "Shotgun Ammo",
            },
            .Other => "Misc Item",
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
        // ArrayList.deinit requires the allocator argument in 0.15
        self.items.deinit(self.allocator);
    }

    pub fn addItem(self: *Inventory, item: Item) !void {
        for (self.items.items) |*it| {
            if (it.item_type == item.item_type and std.meta.eql(it.variant, item.variant)) {
                it.quantity += item.quantity;
                return;
            }
        }
        try self.items.append(self.allocator, item);
    }

    pub fn removeItem(self: *Inventory, item_type: ItemType, variant: @TypeOf(Item.variant), amount: u32) void {
        var i: usize = 0;
        while (i < self.items.items.len) : (i += 1) {
            if (self.items.items[i].item_type == item_type and std.meta.eql(self.items.items[i].variant, variant)) {
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
