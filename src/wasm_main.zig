const std = @import("std");

// Simple WASM-compatible game engine
const WasmEngine = struct {
    width: u32,
    height: u32,
    buffer: []u8,
    x: i32 = 10,
    y: i32 = 10,

    const Self = @This();

    pub fn init(width: u32, height: u32) Self {
        // For WASM, we'll use a simple fixed buffer
        const size = width * height;
        const buffer = std.heap.page_allocator.alloc(u8, size) catch {
            // Use the global static buffer as fallback
            const fallback_size = 80 * 24;
            const fallback_buffer = wasm_allocator_buffer[0..fallback_size];
            @memset(fallback_buffer, ' ');
            return Self{
                .width = 80,
                .height = 24,
                .buffer = fallback_buffer,
                .x = 10,
                .y = 10,
            };
        };

        // Initialize buffer with spaces
        @memset(buffer, ' ');

        return Self{
            .width = width,
            .height = height,
            .buffer = buffer,
            .x = 10,
            .y = 10,
        };
    }

    pub fn clear(self: *Self) void {
        @memset(self.buffer, ' ');
    }

    pub fn setChar(self: *Self, x: u32, y: u32, ch: u8) void {
        if (x >= self.width or y >= self.height) return;
        const idx = y * self.width + x;
        if (idx < self.buffer.len) {
            self.buffer[idx] = ch;
        }
    }

    pub fn movePlayer(self: *Self, dx: i32, dy: i32) void {
        const new_x = self.x + dx;
        const new_y = self.y + dy;

        // Bounds checking
        if (new_x >= 0 and new_x < @as(i32, @intCast(self.width)) and
            new_y >= 0 and new_y < @as(i32, @intCast(self.height)))
        {
            self.x = new_x;
            self.y = new_y;
        }
    }

    pub fn update(self: *Self) void {
        self.clear();

        // Draw border
        for (0..self.width) |x| {
            self.setChar(@intCast(x), 0, '#');
            self.setChar(@intCast(x), self.height - 1, '#');
        }
        for (0..self.height) |y| {
            self.setChar(0, @intCast(y), '#');
            self.setChar(self.width - 1, @intCast(y), '#');
        }

        // Draw player
        self.setChar(@intCast(self.x), @intCast(self.y), '@');

        // Draw some decorations
        self.setChar(5, 5, '*');
        self.setChar(15, 8, '$');
        self.setChar(25, 12, '&');
    }

    pub fn render(self: *Self) void {
        // Convert buffer to string and output
        var output_buffer: [2048]u8 = undefined;
        var pos: usize = 0;

        // Add clear screen sequence
        const clear_seq = "\x1b[2J\x1b[H";
        for (clear_seq) |c| {
            if (pos < output_buffer.len) {
                output_buffer[pos] = c;
                pos += 1;
            }
        }

        // Add the game screen
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const idx = y * self.width + x;
                if (idx < self.buffer.len and pos < output_buffer.len) {
                    output_buffer[pos] = self.buffer[idx];
                    pos += 1;
                }
            }
            // Add newline
            if (pos < output_buffer.len) {
                output_buffer[pos] = '\n';
                pos += 1;
            }
        }

        // Output to terminal (will be handled by JavaScript)
        consoleWrite(output_buffer[0..pos].ptr, pos);
    }
};

// Global game state
var game_engine: WasmEngine = undefined;
var game_initialized = false;
var last_key: u8 = 0;

// External functions that JavaScript will provide
extern "env" fn consoleWrite(ptr: [*]const u8, len: usize) void;
extern "env" fn consoleLog(message: [*]const u8, len: usize) void;

// Helper function to log messages
fn log(message: []const u8) void {
    consoleLog(message.ptr, message.len);
}

// WASM exports
export fn wasm_init() void {
    game_engine = WasmEngine.init(60, 20);
    game_initialized = true;
    log("Game initialized!");
}

export fn wasm_update() void {
    if (!game_initialized) return;

    game_engine.update();
    game_engine.render();
}

export fn wasm_handle_input(key: u8) void {
    if (!game_initialized) return;

    last_key = key;

    switch (key) {
        'w', 'W' => game_engine.movePlayer(0, -1),
        's', 'S' => game_engine.movePlayer(0, 1),
        'a', 'A' => game_engine.movePlayer(-1, 0),
        'd', 'D' => game_engine.movePlayer(1, 0),
        'q', 'Q', 27 => {}, // Quit (handled by JavaScript)
        else => {},
    }

    // Update and render after input
    wasm_update();
}

export fn wasm_get_last_key() u8 {
    return last_key;
}

export fn main() void {
    log("WASM Game Starting...");

    wasm_init();

    // Initial render
    wasm_update();

    log("Game ready! Use WASD to move, Q to quit.");
}

// Simple allocator for WASM
var wasm_allocator_buffer: [1024 * 64]u8 = undefined;
var wasm_allocator_pos: usize = 0;

fn wasmAlloc(size: usize) ?[*]u8 {
    if (wasm_allocator_pos + size > wasm_allocator_buffer.len) {
        return null;
    }

    const ptr: [*]u8 = @ptrCast(&wasm_allocator_buffer[wasm_allocator_pos]);
    wasm_allocator_pos += size;
    return ptr;
}

export fn wasm_alloc(size: usize) ?[*]u8 {
    return wasmAlloc(size);
}
