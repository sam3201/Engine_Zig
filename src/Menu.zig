// src/Menu.zig
const std = @import("std");
const Engine = @import("Engine.zig");
const Player = @import("Player.zig");

pub const Menu = struct {
    title: []const u8,
    items: []const []const u8,
    selected: usize = 0,
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

    pub fn updateOption(self: *Menu, key: u8, player: *Player) void {
        // For now: if we're on "Change Name" and the user presses a letter key, update player.name
        if (std.mem.eql(u8, self.items[self.selected], "Change Name")) {
            
            if (key >= 'a' and key <= 'z') {
                var buf: [32]u8 = undefined;
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

        // Title
        const title_start = (canvas.width - self.title.len) / 2;
        for (self.title, 0..) |ch, i| {
            const title_item_i32: i32 = @intCast(title_start + i);
            canvas.put(title_item_i32, 2, ch);
            canvas.fillColor(@intCast(title_start + i), 2, white);
        }

        // Menu items
        for (self.items, 0..) |item, i| {
            const y: i32 = @intCast(5 + i * 2);
            const start = (canvas.width - item.len) / 2;
            const color = if (i == self.selected) green else white;

            for (item, 0..) |ch, j| {
                canvas.put(@intCast(start + j), y, ch);
                canvas.fillColor(@intCast(start + j), y, color);
            }
        }
    }
};
