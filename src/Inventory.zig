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
    variant: u8, 
    quantity: u32,

    pub fn initWeapon(w: WeaponType, quantity: u32) Item {
        return Item{ .item_type = .Weapon, .variant = @intFromEnum(w), .quantity = quantity };
    }

    pub fn initArmor(a: ArmorType, quantity: u32) Item {
        return Item{ .item_type = .Armor, .variant = @intFromEnum(a), .quantity = quantity };
    }

    pub fn initConsumable(c: ConsumableType, quantity: u32) Item {
        return Item{ .item_type = .Consumable, .variant = @intFromEnum(c), .quantity = quantity };
    }

    pub fn initAmmo(a: AmmoType, quantity: u32) Item {
        return Item{ .item_type = .Ammo, .variant = @intFromEnum(a), .quantity = quantity };
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
            if (it.item_type == item.item_type and it.variant == item.variant) {
                it.quantity += item.quantity;
                return;
            }
        }
        try self.items.append(item);
    }

    pub fn removeItem(self: *Inventory, item_type: ItemType, variant: u8, amount: u32) void {
        var i: usize = 0;
        while (i < self.items.items.len) : (i += 1) {
            if (self.items.items[i].item_type == item_type and self.items.items[i].variant == variant) {
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
