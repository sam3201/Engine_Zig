const std = @import("std");
const Menu = @import("menu.zig").Menu;

pub fn main() !void {
    var menu = Menu.init(&[_][]const u8{"Start Game", "Options", "Quit"});

    // Overwrite navigation keys to use arrow keys or something else
    menu.setKeys('i', 'k', ' '); // e.g. use I/K for nav, space for select

    var stdin = std.io.getStdIn().reader();
    var buf: [1]u8 = undefined;

    while (true) {
        std.debug.print("\x1B[2J\x1B[H", .{}); // clear screen
        menu.render();

        if (try stdin.read(&buf) == 0) break;
        if (menu.update(buf[0])) |choice| {
            std.debug.print("You chose: {s}\n", .{menu.items[choice]});
            break;
        }
    }
}

