// src/Menu.zig
const std = @import("std");
const Engine = @import("Engine.zig");
const Player = @import("Player.zig");

pub const Menu = struct {
    title: []const u8,
    items: []const []const u8,
    selected: u8 = 0,
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

    pub fn updateOption(self: *Menu, key: u8, player: *Player.Player) void {
        if (std.mem.eql(u8, self.items[self.selected], "Change Name")) {
            if (key >= 'a' and key <= 'z') {
                var buf: [32]usize = undefined;
                const len = std.fmt.bufPrint(&buf, "{c}", .{key}) catch return;
                player.setName(buf[0..len]);
            }
        }
    }

    pub fn update(self: *Menu, key: u8) ?usize {
        if (key == self.key_up) {
            if (self.selected > 0) self.selected -= 1;
        } else if (key == self.key_down) {
            if (self.selected + 1 < self.items.len) self.selected += 1;
        } else if (key == self.key_select) {
            return self.selected;
        }
        return null;
    }

    pub fn draw(self: *Menu, canvas: *Engine.Canvas) void {
        const white = Engine.Color{ .r = 255, .g = 255, .b = 255 };
        const green = Engine.Color{ .r = 0, .g = 255, .b = 0 };

         const items_height = self.items.len * 2 - 1;
            const total_height = 1 + 2 + items_height; 
            const start_y: i32 = @intCast((canvas.height - total_height) / 2);

                    // Title
            const title_x = (canvas.width - self.title.len) / 2;
            const title_y = start_y;

        for (self.title, 0..) |ch, i| {
        canvas.put(@intCast(title_x + i), title_y, ch);
            canvas.fillColor(@intCast(title_x + i), title_y, white);
        }

        // Menu items
        for (self.items, 0..) |item, i| {
            const item_y: i32 = title_y + 3 + @as(i32, @intCast(i)) * 2;
            const item_x = (canvas.width - item.len) / 2;
            const color = if (i == self.selected) green else white;

            for (item, 0..) |ch, j| {
                canvas.put(@intCast(item_x + j), item_y, ch);
                canvas.fillColor(@intCast(item_x + j), item_y, color);            }
        }
    }
};
