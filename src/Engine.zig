const std = @import("std");
const builtin = @import("builtin");
const is_wasm = builtin.target.cpu.arch == .wasm32;

const c = @cImport({
    @cInclude("termios.h");
    @cInclude("fcntl.h");
});

const Error = error{WouldBlock};

// Conditional exports for WASM - use C-compatible signatures
pub fn wasm_readKey() callconv(.C) i32 {
    if (comptime !is_wasm) return -1; // Not supported on native

    const result = readKey() catch return -1;
    return if (result) |key| @as(i32, key) else -1;
}

pub fn wasm_handleInput() callconv(.C) i32 {
    if (comptime !is_wasm) return -1; // Not supported on native

    const result = handleInput() catch return -1;
    return if (result) |key| @as(i32, key) else -1;
}

pub fn wasm_run(engine_ptr: ?*anyopaque) callconv(.C) i32 {
    if (comptime !is_wasm) return -1; // Not supported on native

    const engine: *Engine = @ptrCast(@alignCast(engine_ptr orelse return -1));
    engine.run() catch return -1;
    return 0;
}

// Export symbols only for WASM builds
comptime {
    if (is_wasm) {
        @export(wasm_readKey, .{ .name = "wasm_readKey" });
        @export(wasm_handleInput, .{ .name = "wasm_handleInput" });
        @export(wasm_run, .{ .name = "wasm_run" });
    }
}

pub const TerminalGuard = if (!is_wasm) struct {
    orig: std.posix.termios,
    saved: bool = false,
    orig_flags: usize = 0,

    pub fn init() !TerminalGuard {
        var tg: TerminalGuard = undefined;
        tg.orig = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
        tg.saved = true;

        var raw = tg.orig;
        const LBits = std.meta.Int(.unsigned, @bitSizeOf(@TypeOf(raw.lflag)));
        var lbits: LBits = @bitCast(raw.lflag);
        const ICANON_bits: LBits = @intCast(c.ICANON);
        const ECHO_bits: LBits = @intCast(c.ECHO);
        lbits &= ~(ICANON_bits | ECHO_bits);
        raw.lflag = @bitCast(lbits);

        raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;

        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw);

        tg.orig_flags = try std.posix.fcntl(std.posix.STDIN_FILENO, std.posix.F.GETFL, 0);
        _ = try std.posix.fcntl(std.posix.STDIN_FILENO, std.posix.F.SETFL, tg.orig_flags | 0x0004);
        _ = try std.posix.write(std.posix.STDOUT_FILENO, "\x1b[?25l");

        return tg;
    }

    pub fn deinit(self: *TerminalGuard) void {
        _ = std.posix.write(std.posix.STDOUT_FILENO, "\x1b[?25h") catch {};
        if (self.saved) std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, self.orig) catch {};
        _ = std.posix.fcntl(std.posix.STDIN_FILENO, std.posix.F.SETFL, self.orig_flags) catch {};
    }
} else struct {
    pub fn init() !TerminalGuard {
        return TerminalGuard{};
    }

    pub fn deinit(_: *TerminalGuard) void {}
};

pub fn readKey() !?u8 {
    if (!is_wasm) {
        var byte: [1]u8 = undefined;
        const n = std.posix.read(std.posix.STDIN_FILENO, &byte) catch |err| switch (err) {
            error.WouldBlock => return null,
            else => |e| return e,
        };
        if (n == 0) return null;
        return byte[0];
    } else {
        return null;
    }
}

pub fn handleInput() !?u8 {
    return try readKey();
}

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
    color: Color = .{},

    pub fn init(x: i32, y: i32, w: i32, h: i32, id: u32, ch: u8, vx: i32, vy: i32, color: Color) Renderable {
        return .{ .x = x, .y = y, .width = w, .height = h, .id = id, .ch = ch, .vx = vx, .vy = vy, .color = color };
    }

    pub fn deinit(_: *Renderable) void {}
};

pub const Clock = struct {
    target: f64,
    last: i128,
    now: i128,

    pub fn init(fps: f64) Clock {
        const now = std.time.nanoTimestamp();
        return .{
            .target = std.time.ns_per_s / fps,
            .last = now,
            .now = now,
        };
    }

    pub fn tick(self: *Clock) void {
        self.last = self.now;
        self.now = @intCast(std.time.nanoTimestamp());
    }

    pub fn sleepUntilNextFrame(self: *Clock) void {
        const last: f64 = @floatFromInt(self.last);
        const now: f64 = @floatFromInt(self.now);
        const diff = last + self.target - now;
        const sleep_ns: u64 = @intFromFloat(if (diff > 0) diff else 0);
        std.time.sleep(sleep_ns);
    }

    pub fn deinit(_: *Clock) void {}
};

pub const Canvas = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    colors: []Color,
    buf: []u8,
    scene: std.ArrayList(Renderable),
    updateFn: ?UpdateFn = null,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Canvas {
        var canvas = Canvas{
            .allocator = allocator,
            .width = width,
            .height = height,
            .colors = try allocator.alloc(Color, width * height),
            .buf = try allocator.alloc(u8, width * height),
            .scene = try std.ArrayList(Renderable).initCapacity(allocator, 16),
        };
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
        for (self.colors, 0..) |_, i| self.colors[i] = color;
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
        var yy = y;
        while (yy <= y + h - 1) : (yy += 1) {
            var xx = x;
            while (xx <= x + w - 1) : (xx += 1) {
                self.put(xx, yy, ch);
            }
        }
    }

    pub fn flushToTerminal(self: *Canvas) void {
        const stdout = std.io.getStdOut().writer();
        _ = stdout.write("\x1b[H") catch {};

        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const i = y * self.width + x;
                const color = self.colors[i];
                const ch = self.buf[i];

                const esc = std.fmt.allocPrint(self.allocator, "\x1b[38;2;{};{};{}m", .{ color.r, color.g, color.b }) catch continue;
                defer self.allocator.free(esc);
                _ = stdout.write(esc) catch {};
                _ = stdout.writeByte(ch) catch {};
            }
            _ = stdout.write("\n") catch {};
        }
        _ = stdout.write("\x1b[0m") catch {};
    }

    pub fn addRenderable(self: *Canvas, r: Renderable) !void {
        try self.scene.append(r);
    }

    pub fn update(self: *Canvas) void {
        const width: i32 = @intCast(self.width);
        const height: i32 = @intCast(self.height);

        for (self.scene.items) |*r| {
            r.x += r.vx;
            r.y += r.vy;

            if (r.x >= width) {
                r.x = -r.width;
            } else if (r.x < -r.width) r.x = width;

            if (r.y >= height) {
                r.y = -r.height;
            } else if (r.y < -r.height) r.y = height;
        }
    }

    pub fn render(self: *Canvas) void {
        for (self.scene.items) |r| {
            for (0..@intCast(r.height)) |dy| {
                for (0..@intCast(r.width)) |dx| {
                    const dxi32: i32 = @intCast(dx);
                    const dyi32: i32 = @intCast(dy);
                    const x = r.x + dxi32;
                    const y = r.y + dyi32;
                    self.put(x, y, r.ch);
                    self.fillColor(x, y, r.color);
                }
            }
        }
    }

    pub fn setUpdateFn(self: *Canvas, fn_ptr: UpdateFn) void {
        self.updateFn = fn_ptr;
    }
};

pub const Engine = struct {
    allocator: std.mem.Allocator,
    running: bool,
    canvas: Canvas,
    clock: Clock,
    background_color: Color,
    update: ?*const fn () void = null,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize, fps: f64, bg: Color) !Engine {
        return .{
            .allocator = allocator,
            .running = true,
            .canvas = try Canvas.init(allocator, width, height),
            .clock = Clock.init(fps),
            .background_color = bg,
        };
    }

    pub fn deinit(self: *Engine) void {
        self.canvas.deinit();
    }

    pub fn setUpdateFn(self: *Engine, func: *const fn () void) void {
        self.update = func;
    }

    pub fn run(self: *Engine) !void {
        var term = try TerminalGuard.init();
        defer term.deinit();

        while (self.running) {
            self.clock.tick();

            if (!is_wasm) {
                if (try readKey()) |byte| {
                    if (byte == 'q' or byte == 27) break;
                    if (@hasDecl(@import("root"), "setInput")) {
                        @import("root").setInput(byte);
                    }
                }
            }

            self.canvas.clear(' ', self.background_color);

            if (self.canvas.updateFn) |fn_ptr| {
                fn_ptr(&self.canvas);
            } else {
                self.canvas.update();
            }

            if (self.update) |update_fn| {
                update_fn();
            }

            self.canvas.render();
            self.canvas.flushToTerminal();
            self.clock.sleepUntilNextFrame();
        }

        if (!is_wasm) {
            _ = std.posix.write(std.posix.STDOUT_FILENO, "\x1b[?25h\x1b[0m\n") catch {};
        }
    }
};
