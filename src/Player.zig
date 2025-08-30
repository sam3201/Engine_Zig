// src/Player.zig

const std = @import("std");
const eng = @import("Engine.zig");
const Entity = @import("Entity.zig");
const Inventory = @import("Inventory.zig");

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
    OPENMENU,
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
    inventory: Inventory.Inventory,

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
        };
    }

    pub fn deinit(self: *Player) void {
        if (self.key_bindings.len > 0) {
            self.allocator.free(self.key_bindings);
        }
        self.inventory.deinit();
    }

    pub fn processInput(self: *Player, input: u8) InputAction {
        for (self.key_bindings) |binding| {
            if (binding.key == input) {
                return binding.action;
            }
        }
        return InputAction.None;
    }

    pub fn setName(self: *Player, name: []const u8) void {
        self.name = name;
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

        self.experience_to_next_level += self.level * 25;
    }

    pub fn getLevel(self: Player) i32 {
        return self.level;
    }

    pub fn addItem(self: *Player, item: Inventory.Item) !void {
        try self.inventory.addItem(item);
    }

    pub fn removeItem(self: *Player, name: []const u8, amount: u32) void {
        self.inventory.removeItem(name, amount);
    }

    pub fn draw(self: Player, canvas: *eng.Canvas) void {
        canvas.put(self.entity.x, self.entity.y, self.entity.ch);
        canvas.fillColor(self.entity.x, self.entity.y, self.entity.color);
    }
};

pub const PlayerData = struct {
    name: []const u8,
    health: i32,
    max_health: i32,
    xp: i32,
    level: i32,
    experience: i32,
    experience_to_next_level: i32,
    key_bindings: []KeyBinding,
    // TODO: inventory []Item when we add inventory: []u8,
};

// ─────────────────────────────────────────────────────────────
// Bindings
// ─────────────────────────────────────────────────────────────

pub const WASD_BINDINGS = [_]KeyBinding{
    .{ .key = 'w', .action = .UP },
    .{ .key = 'W', .action = .UP },
    .{ .key = 's', .action = .DOWN },
    .{ .key = 'S', .action = .DOWN },
    .{ .key = 'a', .action = .LEFT },
    .{ .key = 'A', .action = .LEFT },
    .{ .key = 'd', .action = .RIGHT },
    .{ .key = 'D', .action = .RIGHT },
    .{ .key = 'e', .action = .INTERACT },
    .{ .key = 'E', .action = .INTERACT },
    .{ .key = ' ', .action = .ATTACK },
    .{ .key = 'i', .action = .OPENINVENTORY },
    .{ .key = 'I', .action = .OPENINVENTORY },
};

pub const ARROW_BINDINGS = [_]KeyBinding{
    .{ .key = 'k', .action = .UP },
    .{ .key = 'j', .action = .DOWN },
    .{ .key = 'h', .action = .LEFT },
    .{ .key = 'l', .action = .RIGHT },
    .{ .key = 'e', .action = .INTERACT },
    .{ .key = ' ', .action = .ATTACK },
    .{ .key = 'i', .action = .OPENINVENTORY },
};

// ─────────────────────────────────────────────────────────────
// Factories
// ─────────────────────────────────────────────────────────────

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
        1, // width
        1, // height
        '@',
        eng.Color{ .r = 255, .g = 255, .b = 0 },
        bindings,
    );
}

pub fn save(self: Player, path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    const writer = file.writer();
    try std.json.stringify(.{
        .name = self.name,
        .health = self.health,
        .max_health = self.max_health,
        .xp = self.xp,
        .level = self.level,
        .experience = self.experience,
        .experience_to_next_level = self.experience_to_next_level,
        .key_bindings = self.key_bindings,
        .inventory = self.inventory,
    }, .{}, writer);
}

pub fn load(allocator: std.mem.Allocator, path: []const u8) !Player {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    const buf = try allocator.alloc(u8, stat.size);
    defer allocator.free(buf);

    _ = try file.readAll(buf);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, buf, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    const id: i32 = @intCast(obj.get("id").?.integer);
    const name = obj.get("name").?.string;
    const health: i32 = @intCast(obj.get("health").?.integer);
    const speed = obj.get("speed").?.integer;
    const max_health: i32 = @intCast(obj.get("max_health").?.integer);
    const xp: i32 = @intCast(obj.get("xp").?.integer);
    const level: i32 = @intCast(obj.get("level").?.integer);
    const experience: i32 = @intCast(obj.get("experience").?.integer);
    const experience_to_next_level: i32 = @intCast(obj.get("experience_to_next_level").?.integer);
    const inv_json = obj.get("inventory").?.array;
    const key_json = obj.get("key_bindings").?.array;
    const key_bindings = try allocator.alloc(KeyBinding, key_json.items.len);
    for (key_json.items, 0..) |b, i| {
        key_bindings[i] = KeyBinding{
            .key = @intCast(b.object.get("key").?.integer),
            .action = @enumFromInt(b.object.get("action").?.integer),
        };
    }
    const inv = try allocator.alloc(Inventory.Item, inv_json.items.len);
    for (inv_json.items, 0..) |it, i| {
        inv[i] = Inventory.Item{
            .id = @intCast(it.object.get("id").?.integer),
            .name = it.object.get("name").?.string,
            .quantity = @intCast(it.object.get("quantity").?.integer),
        };
    }
    var inventory = try allocator.alloc(Inventory.Item, inv_json.items.len);
    for (inv_json.items, 0..) |it, i| {
        inventory[i] = Inventory.Item{
            .id = @intCast(it.object.get("id").?.integer),
            .name = it.object.get("name").?.string,
            .quantity = @intCast(it.object.get("quantity").?.integer),
        };
    }

    // Load key bindings
    const bindings_json = obj.get("key_bindings").?.array;
    var bindings = try allocator.alloc(KeyBinding, bindings_json.items.len);
    for (bindings_json.items, 0..) |b, i| {
        bindings[i] = KeyBinding{
            .key = @intCast(b.object.get("key").?.integer),
            .action = @enumFromInt(b.object.get("action").?.integer),
        };
    }

    var player = try Player.init(
        allocator,
        5,
        5,
        1,
        1,
        '@',
        eng.Color{ .r = 255, .g = 255, .b = 0 },
        bindings,
    );

    player.health = health;
    player.max_health = max_health;
    player.xp = xp;
    player.speed = speed;
    player.level = level;
    player.experience = experience;
    player.experience_to_next_level = experience_to_next_level;
    player.inventory = inventory;
    player.id = id;
    player.name = name;

    return player;
}

pub fn setKeyBinding(self: *Player, action: InputAction, key: u8) void {
    for (self.key_bindings) |*binding| {
        if (binding.action == action) {
            binding.key = key;
            return;
        }
    }
    // If not found, grow list
    if (self.key_bindings.len < 32) { // arbitrary cap
        self.key_bindings = self.allocator.resize(self.key_bindings, self.key_bindings.len + 1) catch return;
        self.key_bindings[self.key_bindings.len - 1] = KeyBinding{ .key = key, .action = action };
    }
}

pub fn createWASDPlayer(allocator: std.mem.Allocator, x: i32, y: i32) !Player {
    return Player{
        .entity = Entity.Entity.init(
            x,
            y,
            1,
            1,
            Entity.RenderableType.PLAYER.toId(),
            '@',
            eng.Color{ .r = 255, .g = 255, .b = 0 },
        ),
        .key_bindings = (&[_]KeyBinding{
            .{ .key = 'w', .action = .UP },
            .{ .key = 's', .action = .DOWN },
            .{ .key = 'a', .action = .LEFT },
            .{ .key = 'd', .action = .RIGHT },
            .{ .key = 'e', .action = .INTERACT },
            .{ .key = ' ', .action = .ATTACK },
            .{ .key = 'i', .action = .OPENINVENTORY },
        })[0..], 
        .name = "Player",
        .health = 10,
        .max_health = 10,
        .xp = 0,
        .speed = 3,
        .level = 0,
        .experience = 0,
        .experience_to_next_level = 100,
        .inventory = try Inventory.Inventory.init(allocator),
        .allocator = allocator, // don’t forget this!
    };
}

pub fn createArrowPlayer(allocator: std.mem.Allocator, x: i32, y: i32) !Player {
    return Player{ .entity = Entity.Entity.init(
        x,
        y,
        1,
        1,
        Entity.RenderableType.PLAYER.toId(),
        '@',
        eng.Color{ .r = 255, .g = 255, .b = 0 },
    ), .key_bindings = (&[_]KeyBinding{
        .{ .key = "up", .action = .UP },
        .{ .key = "down", .action = .DOWN },
        .{ .key = "left", .action = .LEFT },
        .{ .key = "right", .action = .RIGHT },
        .{ .key = 'e', .action = .INTERACT },
        .{ .key = ' ', .action = .ATTACK },
        .{ .key = 'i', .action = .OPENINVENTORY },
    })[0..], .name = "Player", .health = 10, .max_health = 10, .xp = 0, .speed = 3, .level = 0, .experience = 0, .experience_to_next_level = 100, .inventory = try Inventory.Inventory.init(allocator), .allocator = allocator };
}
