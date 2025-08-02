const std = @import("std");
const eng = @import("Engine.zig");
const Entity = @import("Entity.zig");

pub const InputAction = enum {
    UP,
    DOWN,
    LEFT,
    RIGHT,
    INTERACT,
    ATTACK,
    USEITEM,
    DROPITEM,
    OPENINVENTORY,
    None,
};

pub const KeyBinding = struct {
    key: u8,
    action: InputAction,
};

pub const Player = struct {
    entity: Entity.Entity,
    key_bindings: []KeyBinding,
    allocator: std.mem.Allocator,

    health: i32 = 100,
    max_health: i32 = 100,
    xp: i32 = 0,
    speed: i32 = 1,
    level: i32 = 1,
    experience: i32 = 0,
    experience_to_next_level: i32 = 100,

    id: i32 = 0,
    name: []const u8 = "Nameless",

    pub fn init(
        allocator: std.mem.Allocator,
        start_x: i32,
        start_y: i32,
        width: i32,
        height: i32,
        ch: u8,
        color: eng.Color,
        key_bindings: []const KeyBinding,
    ) !Player {
        const owned_bindings = try allocator.alloc(KeyBinding, key_bindings.len);
        @memcpy(owned_bindings, key_bindings);

        const entity = Entity.Entity.init(start_x, start_y, width, height, Entity.RenderableType.PLAYER.toId(), ch, color);

        return Player{
            .entity = entity,
            .key_bindings = owned_bindings,
            .allocator = allocator,
            .health= 100,
    .max_health= 100,
    .xp= 0,
    .speed= 1,
    .level= 1,
    .experience= 0,
    .experience_to_next_level= 100,

    id= 0,
    name: []const u8 = "Nameless",
        };
    }

    pub fn deinit(self: *Player) void {
        self.allocator.free(self.key_bindings);
        self.entity.deinit();
    }

    pub fn processInput(self: *Player, input: u8) InputAction {
        for (self.key_bindings) |binding| {
            if (binding.key == input) {
                return binding.action;
            }
        }
        return InputAction.None;
    }

    pub fn move(self: *Player, dx: i32, dy: i32) void {
        self.entity.update(dx * self.speed, dy * self.speed);
    }

    pub fn setPosition(self: *Player, x: i32, y: i32) void {
        self.entity.x = x;
        self.entity.y = y;
    }

    pub fn getPosition(self: Player) struct { x: i32, y: i32 } {
        return .{ .x = self.entity.x, .y = self.entity.y };
    }

    pub fn getBounds(self: Player) struct { x: i32, y: i32, width: i32, height: i32 } {
        return .{ .x = self.entity.x, .y = self.entity.y, .width = self.entity.width, .height = self.entity.height };
    }

    pub fn takeDamage(self: *Player, damage: i32) void {
        self.health = @max(0, self.health - damage);
    }

    pub fn heal(self: *Player, amount: i32) void {
        self.health = @min(self.max_health, self.health + amount);
    }

    pub fn isAlive(self: Player) bool {
        return self.health > 0;
    }

    pub fn gainExperience(self: *Player, exp: i32) void {
        self.experience += exp;

        while (self.experience >= self.experience_to_next_level) {
            self.levelUp();
        }
    }

    pub fn levelUp(self: *Player) void {
        self.experience -= self.experience_to_next_level;
        self.level += 1;

        self.max_health += 10;
        self.health = self.max_health;

        self.experience_to_next_level = self.experience_to_next_level + (self.level * 25);
    }

    pub fn getLevel(self: Player) i32 {
        return self.level;
    }

    pub fn draw(self: Player, canvas: *eng.Canvas) void {
        canvas.put(self.entity.x, self.entity.y, self.entity.ch);
        canvas.fillColor(self.entity.x, self.entity.y, self.entity.color);
    }
};

pub const WASD_BINDINGS = [_]KeyBinding{
    .{ .key = 'w', .action = .MoveUp },
    .{ .key = 'W', .action = .MoveUp },
    .{ .key = 's', .action = .MoveDown },
    .{ .key = 'S', .action = .MoveDown },
    .{ .key = 'a', .action = .MoveLeft },
    .{ .key = 'A', .action = .MoveLeft },
    .{ .key = 'd', .action = .MoveRight },
    .{ .key = 'D', .action = .MoveRight },
    .{ .key = 'e', .action = .Interact },
    .{ .key = 'E', .action = .Interact },
    .{ .key = ' ', .action = .Attack },
    .{ .key = 'i', .action = .OpenInventory },
    .{ .key = 'I', .action = .OpenInventory },
};

pub const ARROW_BINDINGS = [_]KeyBinding{
    .{ .key = 'k', .action = .MoveUp },
    .{ .key = 'j', .action = .MoveDown },
    .{ .key = 'h', .action = .MoveLeft },
    .{ .key = 'l', .action = .MoveRight },
    .{ .key = 'e', .action = .Interact },
    .{ .key = ' ', .action = .Attack },
    .{ .key = 'i', .action = .OpenInventory },
};

pub fn createPlayer(
    allocator: std.mem.Allocator,
    start_x: i32,
    start_y: i32,
    bindings: []const KeyBinding,
) !Player {
    return Player.init(
        allocator,
        start_x,
        start_y,
        1,
        1,
        '@',
        eng.Color{ .r = 255, .g = 255, .b = 0 }, // Yellow
        bindings,
    );
}

pub fn createWASDPlayer(
    allocator: std.mem.Allocator,
    start_x: i32,
    start_y: i32,
) !Player {
    return createPlayer(allocator, start_x, start_y, &WASD_BINDINGS);
}

pub fn createVimPlayer(
    allocator: std.mem.Allocator,
    start_x: i32,
    start_y: i32,
) !Player {
    return createPlayer(allocator, start_x, start_y, &ARROW_BINDINGS);
}
