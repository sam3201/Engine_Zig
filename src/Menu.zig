// src/Menu.zig
const std = @import("std");
const Engine = @import("Engine.zig");

pub const Menu = struct {
    title: []const u8,
    items: []const []const u8,
    selected: usize = 0,

    // Navigation keys (configurable in main.zig)
    key_up: u8,
    key_down: u8,
    key_select: u8,

    pub fn init(
        title: []const u8,
        items: []const []const u8,
        key_up: u8,
        key_down: u8,
        key_select: u8,
    ) Menu {
        return .{
            .title = title,
            .items = items,
            .selected = 0,
            .key_up = key_up,
            .key_down = key_down,
            .key_select = key_select,
        };
    }

    pub fn update(self: *Menu, key: u8) ?usize {
        if (key == self.key_up) {
            if (self.selected > 0) self.selected -= 1;
        } else if (key == self.key_down) {
            if (self.selected < self.items.len - 1) self.selected += 1;
        } else if (key == self.key_select) {
            return self.selected; // choice confirmed
        }
        return null;
    }

    pub fn draw(self: *Menu, canvas: *Engine.Canvas) void {
        // Clear background
        canvas.clear(' ', Engine.Color{ .r = 10, .g = 10, .b = 10 });

        const white = Engine.Color{ .r = 255, .g = 255, .b = 255 };
        const green = Engine.Color{ .r = 0, .g = 255, .b = 0 };

        // Draw title centered
        const title_start = (@as(i32, @intCast(canvas.width)) - @as(i32, @intCast(self.title.len))) / 2;
        for (self.title, 0..) |ch, i| {
            canvas.put(title_start + i, 3, ch);
            canvas.fillColor(title_start + i, 3, green);
        }

        // Draw menu options
        var y: i32 = 8;
        for (self.items, 0..) |item, i| {
            const x_start = (@as(i32, @intCast(canvas.width)) - @as(i32, @intCast(item.len))) / 2;
            for (item, 0..) |ch, j| {
                const x = x_start + @intCast(j);
                canvas.put(x, y, ch);
                if (i == self.selected) {
                    // Highlight selected option
                    canvas.fillColor(x, y, green);
                } else {
                    canvas.fillColor(x, y, white);
                }
            }
            y += 2;
        }
    }
};
