const std = @import("std");
const Engine = @import("Engine.zig");
const WorldManager = @import("WorldManager.zig");
const Player = @import("Player.zig");
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const net = std.net;

// Global references for update functions (since Engine.setUpdateFn doesn't support context)
var current_instance: ?*GameInstance = null;
var current_server: ?*GameServer = null;

// Game instance for each client connection
const GameInstance = struct {
    engine: Engine.Engine,
    player: Player.Player,
    client_id: u32,
    is_running: bool,
    thread_handle: ?Thread,
    mutex: Mutex,

    pub fn init(allocator: std.mem.Allocator, client_id: u32, is_wasd: bool) !GameInstance {
        const WIDTH: usize = 40; // Each client gets a smaller window
        const HEIGHT: usize = 24;
        const FPS: f64 = 30;
        const bg_color = if (is_wasd)
            Engine.Color{ .r = 20, .g = 20, .b = 40 } // Dark blue for WASD
        else
            Engine.Color{ .r = 40, .g = 20, .b = 20 }; // Dark red for HJKL

        var engine = try Engine.Engine.init(allocator, WIDTH, HEIGHT, FPS, bg_color);

        const player = if (is_wasd)
            try Player.createWASDPlayer(allocator, 10, 12)
        else
            try createVimPlayerCustom(allocator, 10, 12);

        return GameInstance{
            .engine = engine,
            .player = player,
            .client_id = client_id,
            .is_running = false,
            .thread_handle = null,
            .mutex = Mutex{},
        };
    }

    pub fn deinit(self: *GameInstance) void {
        self.mutex.lock();
        self.is_running = false;
        self.mutex.unlock();

        if (self.thread_handle) |handle| {
            handle.join();
        }

        self.player.deinit();
        self.engine.deinit();
    }

    pub fn start(self: *GameInstance) !void {
        self.mutex.lock();
        self.is_running = true;
        self.mutex.unlock();

        self.thread_handle = try Thread.spawn(.{}, gameLoop, .{self});
    }

    pub fn stop(self: *GameInstance) void {
        self.mutex.lock();
        self.is_running = false;
        self.mutex.unlock();
    }

    pub fn isRunning(self: *GameInstance) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.is_running;
    }

    pub fn processInput(self: *GameInstance, input: u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const action = self.player.processInput(input);
        switch (action) {
            .UP => {
                const new_y = self.player.entity.y - self.player.speed;
                if (new_y >= 0) self.player.move(0, -1);
            },
            .DOWN => {
                const new_y = self.player.entity.y + self.player.speed;
                if (new_y < 24) self.player.move(0, 1);
            },
            .LEFT => {
                const new_x = self.player.entity.x - self.player.speed;
                if (new_x >= 0) self.player.move(-1, 0);
            },
            .RIGHT => {
                const new_x = self.player.entity.x + self.player.speed;
                if (new_x < 40) self.player.move(1, 0);
            },
            else => {},
        }
    }

    fn gameLoop(self: *GameInstance) void {
        std.debug.print("Game instance {d} started on dedicated thread\n", .{self.client_id});

        // Store reference globally for the update function to access
        current_instance = self;

        const UpdateFunctions = struct {
            fn update() void {
                if (current_instance) |instance| {
                    instance.mutex.lock();
                    defer instance.mutex.unlock();

                    // Clear canvas
                    instance.engine.canvas.clear();

                    // Draw player
                    instance.player.draw(&instance.engine.canvas);

                    // Draw UI
                    drawInstanceUI(&instance.engine, instance);
                }
            }
        };

        self.engine.setUpdateFn(&UpdateFunctions.update);

        // Run the engine loop
        self.engine.run() catch |err| {
            std.debug.print("Engine error for instance {d}: {any}\n", .{ self.client_id, err });
        };

        std.debug.print("Game instance {d} terminated\n", .{self.client_id});
    }
};

// Server state managing multiple game instances
const GameServer = struct {
    instances: std.ArrayList(*GameInstance),
    server_engine: Engine.Engine,
    allocator: std.mem.Allocator,
    mutex: Mutex,
    next_client_id: u32,

    pub fn init(allocator: std.mem.Allocator) !GameServer {
        // Server has its own master engine for coordination
        const server_engine = try Engine.Engine.init(allocator, 80, 30, 60, Engine.Color{ .r = 10, .g = 10, .b = 10 });

        return GameServer{
            .instances = std.ArrayList(*GameInstance).init(allocator),
            .server_engine = server_engine,
            .allocator = allocator,
            .mutex = Mutex{},
            .next_client_id = 0,
        };
    }

    pub fn deinit(self: *GameServer) void {
        // Stop all instances
        for (self.instances.items) |instance| {
            instance.stop();
            instance.deinit();
            self.allocator.destroy(instance);
        }

        self.instances.deinit();
        self.server_engine.deinit();
    }

    pub fn createInstance(self: *GameServer, is_wasd: bool) !*GameInstance {
        self.mutex.lock();
        defer self.mutex.unlock();

        const client_id = self.next_client_id;
        self.next_client_id += 1;

        const instance = try self.allocator.create(GameInstance);
        instance.* = try GameInstance.init(self.allocator, client_id, is_wasd);

        try self.instances.append(instance);

        std.debug.print("Created game instance {d} ({s})\n", .{ client_id, if (is_wasd) "WASD" else "HJKL" });

        return instance;
    }

    pub fn startServerEngine(self: *GameServer) !void {
        std.debug.print("Starting server master engine\n", .{});

        // Store reference globally for the update function to access
        current_server = self;

        const UpdateFunctions = struct {
            fn update() void {
                if (current_server) |server| {
                    server.mutex.lock();
                    defer server.mutex.unlock();

                    // Clear server canvas
                    server.server_engine.canvas.clear();

                    // Draw server overview
                    drawServerOverview(&server.server_engine, server);
                }
            }
        };

        self.server_engine.setUpdateFn(&UpdateFunctions.update);

        try self.server_engine.run();
    }
};

fn createVimPlayerCustom(allocator: std.mem.Allocator, start_x: i32, start_y: i32) !Player.Player {
    const VIM_BINDINGS = [_]Player.KeyBinding{
        .{ .key = 'k', .action = .UP },
        .{ .key = 'j', .action = .DOWN },
        .{ .key = 'h', .action = .LEFT },
        .{ .key = 'l', .action = .RIGHT },
        .{ .key = 'e', .action = .INTERACT },
        .{ .key = ' ', .action = .ATTACK },
        .{ .key = 'i', .action = .OPENINVENTORY },
    };

    const cyan_color = Engine.Color{ .r = 0, .g = 255, .b = 255 };
    const entity = @import("Entity.zig").Entity.init(start_x, start_y, 1, 1, @import("Entity.zig").RenderableType.PLAYER.toId(), '#', cyan_color);

    const owned_bindings = try allocator.alloc(Player.KeyBinding, VIM_BINDINGS.len);
    @memcpy(owned_bindings, &VIM_BINDINGS);

    return Player.Player{
        .entity = entity,
        .key_bindings = owned_bindings,
        .allocator = allocator,
    };
}

fn drawInstanceUI(engine: *Engine.Engine, instance: *GameInstance) void {
    const white = Engine.Color{ .r = 255, .g = 255, .b = 255 };
    const yellow = Engine.Color{ .r = 255, .g = 255, .b = 0 };
    const cyan = Engine.Color{ .r = 0, .g = 255, .b = 255 };

    // Determine if this is a WASD or HJKL instance based on player character
    const is_wasd = instance.player.entity.ch == '@';
    const color = if (is_wasd) yellow else cyan;
    const controls = if (is_wasd) "WASD Controls" else "HJKL Controls";
    const thread_info = std.fmt.allocPrint(std.heap.page_allocator, "Client {d} Thread", .{instance.client_id}) catch return;
    defer std.heap.page_allocator.free(thread_info);

    // Draw title
    for (controls, 0..) |char, i| {
        if (i >= 40) break;
        engine.canvas.put(@intCast(i), 0, char);
        engine.canvas.fillColor(@intCast(i), 0, color);
    }

    // Draw thread info
    for (thread_info, 0..) |char, i| {
        if (i >= 40) break;
        engine.canvas.put(@intCast(i), 1, char);
        engine.canvas.fillColor(@intCast(i), 1, white);
    }

    // Draw player position
    const pos = instance.player.getPosition();
    const pos_text = std.fmt.allocPrint(std.heap.page_allocator, "Position: ({d}, {d})", .{ pos.x, pos.y }) catch return;
    defer std.heap.page_allocator.free(pos_text);

    for (pos_text, 0..) |char, i| {
        if (i >= 40) break;
        engine.canvas.put(@intCast(i), 22, char);
        engine.canvas.fillColor(@intCast(i), 22, white);
    }

    // Draw engine info
    const engine_info = "Dedicated Engine";
    for (engine_info, 0..) |char, i| {
        if (i >= 40) break;
        engine.canvas.put(@intCast(i), 23, char);
        engine.canvas.fillColor(@intCast(i), 23, Engine.Color{ .r = 0, .g = 255, .b = 0 });
    }
}

fn drawServerOverview(engine: *Engine.Engine, server: *GameServer) void {
    const white = Engine.Color{ .r = 255, .g = 255, .b = 255 };
    const green = Engine.Color{ .r = 0, .g = 255, .b = 0 };
    const blue = Engine.Color{ .r = 100, .g = 150, .b = 255 };

    // Server title
    const title = "MULTI-ENGINE GAME SERVER";
    const title_start = (80 - title.len) / 2;
    for (title, 0..) |char, i| {
        engine.canvas.put(@intCast(title_start + i), 2, char);
        engine.canvas.fillColor(@intCast(title_start + i), 2, green);
    }

    // CPU info
    const cpu_count = Thread.getCpuCount() catch 1;
    const cpu_text = std.fmt.allocPrint(std.heap.page_allocator, "Available CPU Cores: {d}", .{cpu_count}) catch return;
    defer std.heap.page_allocator.free(cpu_text);

    for (cpu_text, 0..) |char, i| {
        engine.canvas.put(@intCast(i + 5), 5, char);
        engine.canvas.fillColor(@intCast(i + 5), 5, white);
    }

    // Active instances count
    const instance_text = std.fmt.allocPrint(std.heap.page_allocator, "Active Game Instances: {d}", .{server.instances.items.len}) catch return;
    defer std.heap.page_allocator.free(instance_text);

    for (instance_text, 0..) |char, i| {
        engine.canvas.put(@intCast(i + 5), 7, char);
        engine.canvas.fillColor(@intCast(i + 5), 7, blue);
    }

    // List running instances
    var y_offset: i32 = 10;
    for (server.instances.items, 0..) |instance, i| {
        if (y_offset >= 25) break;

        const is_wasd = instance.player.entity.ch == '@';
        const status_text = std.fmt.allocPrint(std.heap.page_allocator, "Instance {d}: {s} - {s} - Thread: {s}", .{ instance.client_id, if (is_wasd) "WASD" else "HJKL", if (instance.isRunning()) "RUNNING" else "STOPPED", if (instance.thread_handle != null) "Active" else "None" }) catch continue;
        defer std.heap.page_allocator.free(status_text);

        const color = if (instance.isRunning()) green else Engine.Color{ .r = 255, .g = 100, .b = 100 };

        for (status_text, 0..) |char, j| {
            if (j >= 75) break;
            engine.canvas.put(@intCast(j + 5), y_offset, char);
            engine.canvas.fillColor(@intCast(j + 5), y_offset, color);
        }

        y_offset += 1;
    }

    // Architecture info
    const arch_info = [_][]const u8{
        "ARCHITECTURE:",
        "- Server Engine: Master coordination",
        "- Client Engines: Individual game instances",
        "- Each client: Dedicated thread + canvas",
        "- True concurrent processing",
    };

    y_offset = 20;
    for (arch_info) |line| {
        if (y_offset >= 30) break;

        for (line, 0..) |char, i| {
            if (i >= 75) break;
            engine.canvas.put(@intCast(i + 2), y_offset, char);
            engine.canvas.fillColor(@intCast(i + 2), y_offset, white);
        }
        y_offset += 1;
    }
}

// Simulate network input handling
fn simulateNetworkInput(instance: *GameInstance, input_sequence: []const u8) void {
    std.debug.print("Simulating input for client {d}\n", .{instance.client_id});

    for (input_sequence) |input| {
        instance.processInput(input);
        std.time.sleep(100_000_000); // 100ms delay between inputs

        if (!instance.isRunning()) break;
    }
}

pub fn main() !void {
    std.debug.print("Starting Multi-Engine Game Server\n", .{});
    std.debug.print("Available CPU cores: {d}\n", .{Thread.getCpuCount() catch 1});

    var server = try GameServer.init(std.heap.page_allocator);
    defer server.deinit();

    // Create two game instances (simulating two client connections)
    const instance1 = try server.createInstance(true); // WASD player
    const instance2 = try server.createInstance(false); // HJKL player

    // Start both game instances on separate threads
    try instance1.start();
    try instance2.start();

    // Simulate network input for testing
    const input_thread1 = try Thread.spawn(.{}, simulateNetworkInput, .{ instance1, "wwwwssssaaaadddwwww" });

    const input_thread2 = try Thread.spawn(.{}, simulateNetworkInput, .{ instance2, "kkkkjjjjhhhhllllkkkk" });

    // Start server master engine (this will block until exit)
    try server.startServerEngine();

    // Cleanup
    instance1.stop();
    instance2.stop();

    input_thread1.join();
    input_thread2.join();

    std.debug.print("Multi-Engine Game Server terminated\n", .{});
}

pub fn setInput(input: u8) void {
    // This would be called by the main engine input system
    // In a real implementation, you'd route input to the appropriate instance
    _ = input;
}

