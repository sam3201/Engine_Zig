const std = @import("std");

pub const Menu = struct {
    options: []const []const u8,
    selected_index: usize,

    pub fn init(options: []const []const u8) Menu {
        return Menu{
            .options = options,
            .selected_index = 0,
        };
    }

    fn display(self: *Menu) void {
        std.debug.print("\x1B[2J\x1B[H", .{}); // clear screen
        std.debug.print("Use ↑/↓ and Enter\n\n", .{});
        for (self.options, 0..) |opt, idx| {
            if (idx == self.selected_index) {
                std.debug.print("> {s}\n", .{opt});
            } else {
                std.debug.print("  {s}\n", .{opt});
            }
        }
    }

    pub fn handleSelection(self: *Menu) usize {
        const stdin = std.io.getStdIn().reader();

        while (true) {
            self.display();
            const c = stdin.readByte() catch continue;

            switch (c) {
                0x1B => { // escape sequence
                    const seq1 = stdin.readByte() catch continue;
                    const seq2 = stdin.readByte() catch continue;
                    if (seq1 == '[') {
                        switch (seq2) {
                            'A' => if (self.selected_index > 0) self.selected_index -= 1, // up
                            'B' => if (self.selected_index < self.options.len - 1) self.selected_index += 1, // down
                            else => {},
                        }
                    }
                },
                '\r', '\n' => return self.selected_index, // Enter
                else => {},
            }
        }
    }
};

pub const Prompt = struct {
    prompt: []const u8,
    buffer: [128]u8 = undefined,
    len: usize = 0,

    pub fn init(prompt: []const u8) Prompt {
        return Prompt{ .prompt = prompt };
    }

    pub fn run(self: *Prompt, allocator: std.mem.Allocator) ![]const u8 {
        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdOut().writer();

        self.len = 0;

        while (true) {
            try stdout.print("\r{s}: {s}", .{ self.prompt, self.buffer[0..self.len] });
            const c = stdin.readByte() catch continue;

            switch (c) {
                '\r', '\n' => {
                    try stdout.print("\n", .{});
                    return try allocator.dupe(u8, self.buffer[0..self.len]);
                },
                0x7F => if (self.len > 0) self.len -= 1, // backspace
                else => if (self.len < self.buffer.len) {
                    self.buffer[self.len] = c;
                    self.len += 1;
                },
            }
        }
    }
};

