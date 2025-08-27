const std = @import("std");

pub const Menu = struct {
    items: []const []const u8,
    selected: usize = 0,

    // Default navigation keys (can be overwritten in main.zig)
    key_up: u8 = 'w',
    key_down: u8 = 's',
    key_select: u8 = '\n',

    pub fn init(items: []const []const u8) Menu {
        return Menu{ .items = items };
    }

    pub fn setKeys(self: *Menu, up: u8, down: u8, select: u8) void {
        self.key_up = up;
        self.key_down = down;
        self.key_select = select;
    }

    pub fn update(self: *Menu, key: u8) ?usize {
        if (key == self.key_up) {
            if (self.selected > 0) self.selected -= 1;
        } else if (key == self.key_down) {
            if (self.selected < self.items.len - 1) self.selected += 1;
        } else if (key == self.key_select) {
            return self.selected; // Return chosen item
        }
        return null;
    }

    pub fn render(self: *Menu) void {
        for (self.items, 0..) |item, i| {
            if (i == self.selected) {
                std.debug.print("> {s}\n", .{item});
            } else {
                std.debug.print("  {s}\n", .{item});
            }
        }
    }
};
