const std = @import("std");
const eng = @import("Engine.zig");
const Entity = @import("Entity.zig");
const Player = @import("Player.zig");

pub const Tile = enum {
    Empty,
    Block,
};

pub const Chunk = struct {
    width: usize,
    height: usize,
    tiles: []Tile,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Chunk {
        const tiles = try allocator.alloc(Tile, width * height);
        var chunk = Chunk{
            .width = width,
            .height = height,
            .tiles = tiles,
            .allocator = allocator,
        };
        chunk.generateSurface();
        return chunk;
    }

    pub fn deinit(self: *Chunk) void {
        self.allocator.free(self.tiles);
    }

    pub fn generateSurface(self: *Chunk) void {
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const idx = y * self.width + x;
                if (x == 0 or y == 0 or x == self.width - 1 or y == self.height - 1) {
                    self.tiles[idx] = .Block;
                } else {
                    self.tiles[idx] = .Empty;
                }
            }
        }
    }

    pub fn getTile(self: Chunk, x: usize, y: usize) Tile {
        return self.tiles[y * self.width + x];
    }

    pub fn setTile(self: *Chunk, x: usize, y: usize, tile: Tile) void {
        self.tiles[y * self.width + x] = tile;
    }
};

pub const World = struct {
    chunk: Chunk,
    canvas: *eng.Canvas,
    player: Player.Player,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize, canvas: *eng.Canvas) !World {
        const chunk = try Chunk.init(allocator, width, height);

        const player_x: i32 = @intCast(width / 2);
        const player_y: i32 = @intCast(height / 2);

        const player = try Player.createWASDPlayer(allocator, player_x, player_y);

        return World{
            .chunk = chunk,
            .canvas = canvas,
            .player = player,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *World) void {
        self.chunk.deinit();
        self.player.deinit();
    }

    pub fn handlePlayerAction(self: *World, action: Player.InputAction) void {
        switch (action) {
            .MoveUp => self.tryMovePlayer(0, -1),
            .MoveDown => self.tryMovePlayer(0, 1),
            .MoveLeft => self.tryMovePlayer(-1, 0),
            .MoveRight => self.tryMovePlayer(1, 0),
            .Interact => self.playerInteract(),
            .Attack => self.playerAttack(),
            .UseItem => self.playerUseItem(),
            .OpenInventory => self.playerOpenInventory(),
            .None => {},
        }
    }

    pub fn processPlayerInput(self: *World, input: u8) void {
        const action = self.player.processInput(input);
        self.handlePlayerAction(action);
    }

    fn tryMovePlayer(self: *World, dx: i32, dy: i32) void {
        const pos = self.player.getPosition();
        const new_x = pos.x + dx;
        const new_y = pos.y + dy;

        if (new_x < 0 or new_x >= self.chunk.width or new_y < 0 or new_y >= self.chunk.height) {
            return;
        }

        const tile = self.chunk.getTile(@intCast(new_x), @intCast(new_y));
        if (tile == .Empty) {
            self.player.move(dx, dy);
        }
    }

    fn playerInteract(self: *World) void {
        // TODO:
        _ = self;
    }

    fn playerAttack(self: *World) void {
        // TODO:
        _ = self;
    }

    fn playerUseItem(self: *World) void {
        // TODO:
        _ = self;
    }

    fn playerOpenInventory(self: *World) void {
        // TODO:
        _ = self;
    }

    pub fn draw(self: *World) void {
        // Draw the world tiles
        for (0..self.chunk.height) |y| {
            for (0..self.chunk.width) |x| {
                const tile = self.chunk.getTile(x, y);
                const ch: u8 = switch (tile) {
                    .Empty => '.',
                    .Block => '#',
                };
                const color = switch (tile) {
                    .Empty => eng.Color{ .r = 50, .g = 50, .b = 50 },
                    .Block => eng.Color{ .r = 255, .g = 255, .b = 255 },
                };

                self.canvas.put(@intCast(x), @intCast(y), ch);
                self.canvas.fillColor(@intCast(x), @intCast(y), color);
            }
        }

        self.player.draw(self.canvas);

        self.drawHUD();
    }

    fn drawHUD(self: *World) void {
        const health_text = std.fmt.allocPrint(self.allocator, " HP: {}/{} ", .{ self.player.health, self.player.max_health }) catch return;
        defer self.allocator.free(health_text);

        const quarter_health = @divTrunc(self.player.max_health, 4);
        const half_health = @divTrunc(self.player.max_health, 2);

        const health_color = if (self.player.health < quarter_health)
            eng.Color{ .r = 255, .g = 0, .b = 0 }
        else if (self.player.health < half_health)
            eng.Color{ .r = 255, .g = 255, .b = 0 }
        else
            eng.Color{ .r = 0, .g = 255, .b = 0 };

        for (health_text, 0..) |ch, i| {
            self.canvas.put(@intCast(i), 0, ch);
            self.canvas.fillColor(@intCast(i), 0, health_color);
        }
    }
};
