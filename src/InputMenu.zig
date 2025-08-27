const std = @import("std");

pub const InputMenu = struct {
    options: []const []const u8, // array of option strings
    selected_index: usize,       // currently highlighted option
    stdin: *std.io.Reader = &std.io.stdin().reader(),

    pub fn init(options: []const []const u8) InputMenu {
        return InputMenu{
            .options = options,
            .selected_index = 0,
        };
    }

    pub fn display(self: *InputMenu) void {
        std.debug.clearScreen();
        std.debug.print("Use arrow keys to move and Enter to select\n\n", .{});
        for (self.options) |option, idx| {
            if (idx == self.selected_index) {
                std.debug.print("> {s}\n", .{option});
            } else {
                std.debug.print("  {s}\n", .{option});
            }
        }
    }

    pub fn handle_input(self: *InputMenu) usize {
        while (true) {
            self.display();
            const c = std.io.getStdIn().readByte() catch continue;

            switch (c) {
                0x1B => { // ESC sequence (arrows)
                    const seq1 = std.io.getStdIn().readByte() catch continue;
                    const seq2 = std.io.getStdIn().readByte() catch continue;
                    if (seq1 == 0x5B) {
                        switch (seq2) {
                            0x41 => if (self.selected_index > 0) self.selected_index -= 1; // up
                            0x42 => if (self.selected_index < self.options.len - 1) self.selected_index += 1; // down
                            else => {},
                        }
                    }
                },
                0x0A, 0x0D => return self.selected_index, // Enter
                else => {},
            }
        }
    }
};

