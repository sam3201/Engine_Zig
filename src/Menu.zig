const std = @import("std");

pub const Menu = struct {
    title: []const u8,
    options: [][]const u8,
    selected: usize,

    // New: custom key bindings (optional)
    key_up: u32,
    key_down: u32,
    key_confirm: u32,

    pub fn init(
        title: []const u8,
        options: [][]const u8,
        key_up: u32,
        key_down: u32,
        key_confirm: u32,
    ) Menu {
        return Menu{
            .title = title,
            .options = options,
            .selected = 0,
            .key_up = key_up,
            .key_down = key_down,
            .key_confirm = key_confirm,
        };
    }

    pub fn update(self: *Menu, pressed_key: u32) ?usize {
        if (pressed_key == self.key_up) {
            if (self.selected == 0) {
                self.selected = self.options.len - 1;
            } else {
                self.selected -= 1;
            }
        } else if (pressed_key == self.key_down) {
            self.selected = (self.selected + 1) % self.options.len;
        } else if (pressed_key == self.key_confirm) {
            return self.selected;
        }
        return null;
    }

    pub fn draw(self: *const Menu) void {
        std.debug.print("{s}\n", .{self.title});
        for (self.options, 0..) |opt, i| {
            if (i == self.selected) {
                std.debug.print("> {s}\n", .{opt});
            } else {
                std.debug.print("  {s}\n", .{opt});
            }
        }
    }
};
