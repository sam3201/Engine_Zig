const std = @import("std");
const rl = @import("raylib");

pub const Menu = struct {
    items: []const []const u8,
    selected: usize,
    up_key: c_int,
    down_key: c_int,
    confirm_key: c_int,

    pub fn init(items: []const []const u8) Menu {
        return Menu{
            .items = items,
            .selected = 0,
            // Default mappings (can be overridden later)
            .up_key = rl.KEY_UP,
            .down_key = rl.KEY_DOWN,
            .confirm_key = rl.KEY_ENTER,
        };
    }

    /// Allows overwriting keys
    pub fn setKeys(self: *Menu, up: c_int, down: c_int, confirm: c_int) void {
        self.up_key = up;
        self.down_key = down;
        self.confirm_key = confirm;
    }

    pub fn update(self: *Menu) ?usize {
        if (rl.IsKeyPressed(self.up_key)) {
            if (self.selected > 0) self.selected -= 1
            else self.selected = self.items.len - 1;
        }
        if (rl.IsKeyPressed(self.down_key)) {
            self.selected = (self.selected + 1) % self.items.len;
        }
        if (rl.IsKeyPressed(self.confirm_key)) {
            return self.selected; // return index of chosen item
        }
        return null;
    }

    pub fn draw(self: *Menu, x: f32, y: f32, fontSize: f32) void {
        for (self.items, 0..) |item, i| {
            const color = if (i == self.selected) rl.RED else rl.DARKGRAY;
            rl.DrawText(item.ptr, @intFromFloat(x), @intFromFloat(y + @as(f32, @floatFromInt(i)) * fontSize * 1.5), @intFromFloat(fontSize), color);
        }
    }
};

