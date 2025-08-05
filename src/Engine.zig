// src/Engine.zig

const std = @import("std");
const c = @cImport({
    @cInclude("termios.h");
    @cInclude("fcntl.h");
});
const main = @import("main.zig");

const UpdateFn = *const fn (*Canvas) void;

pub const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
};

pub const Renderable = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    id: u32,
    ch: u8 = ' ',
    vx: i32 = 0,
    vy: i32 = 0,
    color: Color = Color{ .r = 0, .g = 0, .b = 0 },

    pub fn init(x: i32, y: i32, w: i32, h: i32, id: u32, ch: u8, vx: i32, vy: i32, color: Color) Renderable {
        return .{ .x = x, .y = y, .width = w, .height = h, .id = id, .ch = ch, .vx = vx, .vy = vy, .color = color };
    }

    pub fn deinit(self: *Renderable) void {
        _ = self;
    }
};

pub const Clock = struct {
    target: f64,
    last: i128,
    now: i128,

    pub fn init(fps: f64) Clock {
        return .{
            .target = std.time.ns_per_s / fps,
            .last = std.time.nanoTimestamp(),
            .now = std.time.nanoTimestamp(),
        };
    }

    pub fn setFps(self: *Clock, fps: f64) void {
        self.target = std.time.ns_per_s / fps;
    }

    pub fn tick(self: *Clock) void {
        self.last = self.now;
        self.now = @intCast(std.time.nanoTimestamp());
    }

    pub fn sleepUntilNextFrame(self: *Clock) void {
        const frame_last_f64: f64 = @floatFromInt(self.last);
        const frame_end: f64 = frame_last_f64 + self.target;
        const now_f64: f64 = @floatFromInt(self.now);
        const diff: f64 = if (frame_end > now_f64) frame_end - now_f64 else 0;
        const sleep_ns: u64 = @intFromFloat(diff);
        std.time.sleep(sleep_ns);
    }

    pub fn deinit(self: *Clock) void {
        _ = self;
    }
};

pub const Canvas = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    colors: []Color,
    buf: []u8,
    scene: std.ArrayList(Renderable),
    updateFn: ?UpdateFn = null, // Changed to null

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Canvas {
        var canvas = Canvas{
            .allocator = allocator,
            .width = width,
            .height = height,
            .colors = try allocator.alloc(Color, width * height),
            .buf = try allocator.alloc(u8, width * height),
            .scene = try std.ArrayList(Renderable).initCapacity(allocator, 16),
            .updateFn = null,
        };
        // Set the default update function
        canvas.updateFn = Canvas.update;
        return canvas;
    }

    pub fn deinit(self: *Canvas) void {
        for (self.scene.items) |*r| r.deinit();
        self.scene.deinit();
        self.allocator.free(self.colors);
        self.allocator.free(self.buf);
    }

    pub fn clear(self: *Canvas, ch: u8, color: Color) void {
        @memset(self.buf, ch);
        for (self.colors, 0..) |_, i| {
            self.colors[i] = color;
        }
    }

    pub fn put(self: *Canvas, x: i32, y: i32, ch: u8) void {
        if (x < 0 or y < 0) return;
        const ux: usize = @intCast(x);
        const uy: usize = @intCast(y);
        if (ux >= self.width or uy >= self.height) return;
        self.buf[uy * self.width + ux] = ch;
    }

    pub fn fillColor(self: *Canvas, x: i32, y: i32, color: Color) void {
        if (x < 0 or y < 0) return;
        const ux: usize = @intCast(x);
        const uy: usize = @intCast(y);
        if (ux >= self.width or uy >= self.height) return;
        self.colors[uy * self.width + ux] = color;
    }

    pub fn fillRect(self: *Canvas, x: i32, y: i32, w: i32, h: i32, ch: u8) void {
        const x0: i32 = x;
        const y0: i32 = y;
        const x1: i32 = x + w - 1;
        const y1: i32 = y + h - 1;

        var yy = y0;
        while (yy <= y1) : (yy += 1) {
            var xx = x0;
            while (xx <= x1) : (xx += 1) {
                self.put(xx, yy, ch);
            }
        }
    }

    pub fn flushToTerminal(self: *Canvas) void {
        const stdout = std.io.getStdOut().writer();

        _ = stdout.write("\x1b[H") catch {};

        var y: usize = 0;
        while (y < self.height) : (y += 1) {
            var x: usize = 0;
            while (x < self.width) : (x += 1) {
                const idx = y * self.width + x;
                const col = self.colors[idx];
                const ch = self.buf[idx];

                const esc = std.fmt.allocPrint(self.allocator, "\x1b[38;2;{};{};{}m", .{ col.r, col.g, col.b }) catch continue;
                defer self.allocator.free(esc);

                _ = stdout.write(esc) catch {};
                _ = stdout.writeByte(ch) catch {};
            }

            _ = stdout.write("\n") catch {};
        }

        // Reset color
        _ = stdout.write("\x1b[0m") catch {};
    }

    pub fn addRenderable(self: *Canvas, r: Renderable) !void {
        try self.scene.append(r);
    }

    pub fn update(self: *Canvas) void {
        const canvas_width_i32: i32 = @intCast(self.width);
        const canvas_height_i32: i32 = @intCast(self.height);

        for (self.scene.items) |*r| {
            r.x += r.vx;
            r.y += r.vy;

            if (r.x >= canvas_width_i32) {
                r.x = -r.width;
            } else if (r.x < -r.width) {
                r.x = canvas_width_i32;
            }

            if (r.y >= canvas_height_i32) {
                r.y = -r.height;
            } else if (r.y < -r.height) r.y = canvas_height_i32;
        }
    }

    pub fn setUpdateFn(self: *@This(), update_fn: UpdateFn) void {
        self.updateFn = update_fn;
    }

    pub fn render(self: *Canvas) void {
        for (self.scene.items) |r| {
            const x0 = r.x;
            const y0 = r.y;
            const x1 = r.x + r.width - 1;
            const y1 = r.y + r.height - 1;

            var yy = y0;
            while (yy <= y1) : (yy += 1) {
                var xx = x0;
                while (xx <= x1) : (xx += 1) {
                    self.put(xx, yy, r.ch);
                    self.fillColor(xx, yy, r.color);
                }
            }
        }
    }
};

pub const Engine = struct {
    allocator: std.mem.Allocator,
    running: bool,
    canvas: Canvas,
    clock: Clock,
    background_color: Color,

    update: ?*const fn () void = null,

    pub fn init(
        allocator: std.mem.Allocator,
        width: usize,
        height: usize,
        fps: f64,
        background_color: Color,
    ) !Engine {
        return .{
            .allocator = allocator,
            .running = true,
            .canvas = try Canvas.init(allocator, width, height),
            .clock = Clock.init(fps),
            .background_color = background_color,
        };
    }

    pub fn deinit(self: *Engine) void {
        self.canvas.deinit();
    }

    pub fn setUpdateFn(self: *@This(), func: *const fn () void) void {
        self.update = func;
    }

    pub fn run(self: *Engine) !void {
        var term = try TerminalGuard.init();
        defer term.deinit();

        while (self.running) {
            self.clock.tick();

            if (try readKey()) |byte| {
                if (byte == 'q' or byte == 27) {
                    self.running = false;
                    break;
                }
                main.setInput(byte);
            }

            self.canvas.clear(
                ' ',
                self.background_color,
            );

            if (self.canvas.updateFn) |updateFn| {
                updateFn(&self.canvas);
            }

            if (self.update) |updateFn| {
                updateFn();
            }

            self.canvas.render();
            self.canvas.flushToTerminal();
            self.clock.sleepUntilNextFrame();
        }

        _ = std.posix.write(std.posix.STDOUT_FILENO, "\x1b[?25h\x1b[0m\n") catch |err| {
            if (err != error.WouldBlock) return err;
        };
    }
};

pub const TerminalGuard = struct {
    orig: std.posix.termios,
    saved: bool = false,
    orig_flags: usize = 0,

    pub fn init() !TerminalGuard {
        var tg: TerminalGuard = undefined;

        tg.orig = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
        tg.saved = true;

        var raw = tg.orig;

        const LFlag = @TypeOf(raw.lflag);
        const LBits = std.meta.Int(.unsigned, @bitSizeOf(LFlag));
        var lbits: LBits = @bitCast(raw.lflag);
        const ICANON_bits: LBits = @intCast(c.ICANON);
        const ECHO_bits: LBits = @intCast(c.ECHO);
        lbits &= ~(ICANON_bits | ECHO_bits);
        raw.lflag = @bitCast(lbits);

        raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;

        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw);

        const flags: usize = try std.posix.fcntl(std.posix.STDIN_FILENO, std.posix.F.GETFL, 0);
        tg.orig_flags = flags;

        const nonblock_bits: usize = 0x0004;
        _ = try std.posix.fcntl(std.posix.STDIN_FILENO, std.posix.F.SETFL, flags | nonblock_bits);

        _ = try std.posix.write(std.posix.STDOUT_FILENO, "\x1b[?25l");

        return tg;
    }

    pub fn deinit(self: *TerminalGuard) void {
        _ = std.posix.write(std.posix.STDOUT_FILENO, "\x1b[?25h") catch {};

        if (self.saved) {
            std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, self.orig) catch {};
        }
        _ = std.posix.fcntl(std.posix.STDIN_FILENO, std.posix.F.SETFL, self.orig_flags) catch {};
    }
};

pub fn readKey() !?u8 {
    var byte: [1]u8 = undefined;
    const n = std.posix.read(std.posix.STDIN_FILENO, &byte) catch |err| switch (err) {
        error.WouldBlock => return null,
        else => return err,
    };
    if (n == 0) return null;
    return byte[0];
}

pub fn handleInput() !?u8 {
    return try readKey();
}
