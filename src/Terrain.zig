// src/Terrain.zig

const std = @import("std");
const Engine = @import("Engine.zig");

pub const Terrain = struct {
    width: usize,
    height: usize,
    heights: []f32, 
    seed: u64,
    scale: f32,
    octaves: u8,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize, seed: u64, scale: f32, octaves: u8) !Terrain {
        var t = Terrain{
            .width = width,
            .height = height,
            .heights = try allocator.alloc(f32, width * height),
            .seed = seed,
            .scale = scale,
            .octaves = octaves,
        };
        t.generate();
        return t;
    }

    pub fn deinit(self: *Terrain, allocator: std.mem.Allocator) void {
        allocator.free(self.heights);
    }

    fn idx(self: *Terrain, x: usize, y: usize) usize {
        return y * self.width + x;
    }

    pub fn getHeight(self: *const Terrain, x: usize, y: usize) f32 {
        if (x >= self.width or y >= self.height) return 0.0;
        return self.heights[y * self.width + x];
    }

    pub fn sampleAt(self: *const Terrain, xf: f32, yf: f32) f32 {
        if (xf < 0) return 0.0;
        if (yf < 0) return 0.0;
        const x0: usize = @intCast(@floor(xf));
        const y0: usize = @intCast(@floor(yf));
        const x1 = if (x0 + 1 < self.width) x0 + 1 else x0;
        const y1 = if (y0 + 1 < self.height) y0 + 1 else y0;
        const sx = xf - @as(f32, x0);
        const sy = yf - @as(f32, y0);
        const h00 = self.getHeight(x0, y0);
        const h10 = self.getHeight(x1, y0);
        const h01 = self.getHeight(x0, y1);
        const h11 = self.getHeight(x1, y1);
        const ix0 = h00 + (h10 - h00) * sx;
        const ix1 = h01 + (h11 - h01) * sx;
        return ix0 + (ix1 - ix0) * sy;
    }

    pub fn generate(self: *Terrain) void {
        // fractal value noise
        const w = self.width;
        //const h = self.height;
        const max_oct = @as(u32, self.octaves);
        const hrow = self.heights[0..w];
        for (hrow, 0..) |_, y| {
            var x: usize = 0;
            while (x < w) : (x += 1) {
                var amp: f32 = 1.0;
                var freq: f32 = 1.0 / self.scale;
                var sum: f32 = 0.0;
                var norm: f32 = 0.0;
                var o: u32 = 0;
                while (o < max_oct) : (o += 1) {
                    const sx = @as(f32, x) * freq;
                    const sy = @as(f32, y) * freq;
                    sum += amp * Terrain.simpleNoise2D(self.seed + o, sx, sy);
                    norm += amp;
                    amp *= 0.5;
                    freq *= 2.0;
                }
                const val = sum / norm; // -1..1
                self.heights[y * w + x] = (val * 0.5) + 0.5;
            }
        }
    }

    pub fn simpleNoise2D(seed: u64, x: f32, y: f32) f32 {
        const xi: i32 = @intCast(@floor(x));
        const yi: i32 = @intCast(@floor(y));
        const xf = x - @as(f32, xi);
        const yf = y - @as(f32, yi);

        const v00 = Terrain.hashFloat(seed, xi, yi);
        const v10 = Terrain.hashFloat(seed, xi + 1, yi);
        const v01 = Terrain.hashFloat(seed, xi, yi + 1);
        const v11 = Terrain.hashFloat(seed, xi + 1, yi + 1);

        const u = Terrain.smoothstep(xf);
        const v = Terrain.smoothstep(yf);
        const ix0 = v00 + (v10 - v00) * u;
        const ix1 = v01 + (v11 - v01) * u;
        return ix0 + (ix1 - ix0) * v;
    }

    fn smoothstep(t: f32) f32 {
        return t * t * (3.0 - 2.0 * t);
    }

    fn hashFloat(seed: u64, x: i32, y: i32) f32 {
        var h: u64 = @intCast(x) * 0x9E3779B97F4A7C15 + @intCast(u64, y) * 0xBF58476D1CE4E5B9 + seed;
        h = (h ^ (h >> 30)) * 0xBF58476D1CE4E5B9;
        h = (h ^ (h >> 27)) * 0x94D049BB133111EB;
        h = h ^ (h >> 31);
        // map to -1..1
        const f = @as(f32, (h & 0xFFFFFFFFFFFFFFFF)) / @as(f32, 0xFFFFFFFFFFFFFFFF);
        return (f * 2.0) - 1.0;
    }

    pub fn mapMaterial(self: *Terrain, h: f32) struct { ch: u8, color: Engine.Color } {
        // thresholds
        if (h < 0.2) return .{ .ch = '~', .color = Engine.Color{ .r = 20, .g = 60, .b = 180 } };
        if (h < 0.3) return .{ .ch = '.', .color = Engine.Color{ .r = 200, .g = 180, .b = 90 } };
        if (h < 0.6) return .{ .ch = ',', .color = Engine.Color{ .r = 30, .g = 160, .b = 30 } };
        if (h < 0.8) return .{ .ch = '#', .color = Engine.Color{ .r = 120, .g = 70, .b = 20 } };
        return .{ .ch = '*', .color = Engine.Color{ .r = 240, .g = 240, .b = 240 } };
    }

    pub fn renderTopDown(self: *Terrain, canvas: *Engine.Canvas, camera_x: f32, camera_y: f32, scale: f32) void {
        const cw = canvas.width;
        const ch = canvas.height;
        //const cx = @as(f32, cw) / 2.0;
        const cy = @as(f32, ch) / 2.0;
        for (cy, 0..) |_, sy| {
            var sx: usize = 0;
            while (sx < cw) : (sx += 1) {
                const world_x = camera_x - @as(f32, cw) / 2.0 * scale + @as(f32, sx) * scale;
                const world_y = camera_y - @as(f32, ch) / 2.0 * scale + @as(f32, sy) * scale;
                const hval = self.sampleAt(world_x, world_y);
                const m = self.mapMaterial(hval);
                canvas.put(@intCast(sx), @intCast(sy), m.ch);
                canvas.fillColor(@intCast(sx), @intCast(sy), m.color);
            }
        }
    }

    pub fn render3D(self: *Terrain, canvas: *Engine.Canvas, cam_x: f32, cam_y: f32, cam_height: f32, cam_angle: f32, fov: f32, max_dist: f32) void {
        // Simple column renderer (raymarch sample per column)
        const screen_w = @as(f32, canvas.width);
        const screen_h = @as(f32, canvas.height);
        const half_h = screen_h / 2.0;
        //const two_pi = 6.2831855;

        var sx: usize = 0;
        while (sx < canvas.width) : (sx += 1) {
            const rel = (@as(f32, sx) / screen_w) - 0.5; // -0.5..0.5
            const angle = cam_angle + rel * fov;
            var dist: f32 = 1.0;
            var hit: bool = false;
            var hit_h: f32 = 0.0;
            var hit_dist: f32 = 0.0;
            while (dist < max_dist) : (dist += 0.5) {
                const wx = cam_x + dist * std.math.cos(angle);
                const wy = cam_y + dist * std.math.sin(angle);
                if (wx < 0 or wy < 0 or wx >= @as(f32, self.width) or wy >= @as(f32, self.height)) continue;
                const height_at = self.sampleAt(wx, wy);
                // world height relative to camera
                const rel_h = (height_at * 20.0) - cam_height; 
                // project to screen y
                const proj_y = half_h - (rel_h / dist) * 8.0; 
                if (proj_y < half_h) {
                    hit = true;
                    hit_h = height_at;
                    hit_dist = dist;
                    break;
                }
            }

            var y: usize = 0;
            while (y < canvas.height) : (y += 1) {
                if (!hit) {
                    // sky
                    const sky_col = Terrain.skyColor(0.5); 
                    canvas.put(@intCast(sx), @intCast(y), ' ');
                    canvas.fillColor(@intCast(sx), @intCast(y), sky_col);
                } else {
                    const col_top: usize = @intCast(@max(0, @floor((half_h - ( ( (hit_h * 20.0) - cam_height) / hit_dist) * 8.0 )))) ;
                    if (y < col_top) {
                        const sky_col = Terrain.skyColor(0.5);
                        canvas.put(@intCast(sx), @intCast(y), ' ');
                        canvas.fillColor(@intCast(sx), @intCast(y), sky_col);
                    } else {
                        const mat = self.mapMaterial(hit_h);
                        canvas.put(@intCast(sx), @intCast(y), mat.ch);
                        canvas.fillColor(@intCast(sx), @intCast(y), mat.color);
                    }
                }
            }
        }
    }

    pub fn skyColor(time: f32) Engine.Color {
        // simple sky gradient mapped by time(0..1)
        const t = std.math.clamp(time, 0.0, 1.0);
        // day (0.0..0.5) -> blue sky, night (0.5..1.0) -> dark
        const day = if (t < 0.5) 1.0 else 0.0;
        const r: u8 = @intCast(30 + 120 * day);
        const g: u8 = @intCast(60 + 120 * day);
        const b: u8 = @intCast(140 + 60 * day);
        return Engine.Color{ .r = r, .g = g, .b = b };
    }
};

