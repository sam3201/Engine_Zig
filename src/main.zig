const std = @import("std");
const Engine = @import("Engine.zig");
const Player = @import("Player.zig");
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const process = std.process;

// Global references for update functions
var current_instance: ?*GameInstance = null;
var current_server: ?*GameServer = null;

// Terminal spawning utilities for macOS
const TerminalSpawner = struct {
    pub fn spawnInNewTerminal(allocator: std.mem.Allocator, client_id: u32, is_wasd: bool) !process.Child {
        const exe_path = try std.fs.selfExePathAlloc(allocator);
        defer allocator.free(exe_path);

        const instance_args = try std.fmt.allocPrint(allocator, "--client-mode --client-id={d} --is-wasd={}", .{ client_id, is_wasd });
        defer allocator.free(instance_args);

        const full_command = try std.fmt.allocPrint(allocator, "{s} {s}", .{ exe_path, instance_args });
        defer allocator.free(full_command);

        // Try macOS-specific methods first
        if (spawnMacOSTerminal(allocator, full_command)) |child| {
            std.debug.print("Successfully spawned macOS terminal for client {d}\n", .{client_id});
            return child;
        } else |_| {
            // Fall back to standard terminal detection
            const terminal_cmd = detectTerminal() orelse {
                std.debug.print("Warning: Could not detect terminal emulator, falling back to inline mode\n", .{});
                return error.NoTerminalFound;
            };

            std.debug.print("Spawning: {s} {s} {s}\n", .{ terminal_cmd.command, terminal_cmd.flag, full_command });

            var child = process.Child.init(&[_][]const u8{
                terminal_cmd.command,
                terminal_cmd.flag,
                full_command,
            }, allocator);

            child.stdout_behavior = .Ignore;
            child.stderr_behavior = .Ignore;
            child.stdin_behavior = .Ignore;

            try child.spawn();
            std.debug.print("Successfully spawned terminal process for client {d}\n", .{client_id});
            return child;
        }
    }

    fn spawnMacOSTerminal(allocator: std.mem.Allocator, command: []const u8) !process.Child {
        // Try Terminal.app first (more reliable than Ghostty automation)
        const applescript = try std.fmt.allocPrint(allocator,
            \\tell application "Terminal"
            \\    activate
            \\    do script "{s}"
            \\end tell
        , .{command});
        defer allocator.free(applescript);

        var child = process.Child.init(&[_][]const u8{ "osascript", "-e", applescript }, allocator);

        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        child.stdin_behavior = .Ignore;

        try child.spawn();
        return child;
    }

    const TerminalInfo = struct {
        command: []const u8,
        flag: []const u8,
    };

    fn detectTerminal() ?TerminalInfo {
        const terminals = [_]TerminalInfo{
            .{ .command = "alacritty", .flag = "-e" },
            .{ .command = "kitty", .flag = "-e" },
            .{ .command = "wezterm", .flag = "start" },
            .{ .command = "gnome-terminal", .flag = "--" },
            .{ .command = "konsole", .flag = "-e" },
            .{ .command = "xterm", .flag = "-e" },
        };

        for (terminals) |terminal| {
            if (isCommandAvailable(terminal.command)) {
                return terminal;
            }
        }

        return null;
    }

    fn isCommandAvailable(command: []const u8) bool {
        var child = process.Child.init(&[_][]const u8{ "which", command }, std.heap.page_allocator);
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        const result = child.spawnAndWait() catch return false;
        return result == .Exited and result.Exited == 0;
    }
};

// Simple game instance
const GameInstance = struct {
    engine: Engine.Engine,
    player: Player.Player,
    client_id: u32,
    is_running: bool,
    thread_handle: ?Thread,
    mutex: Mutex,
    process_handle: ?process.Child,

    pub fn init(allocator: std.mem.Allocator, client_id: u32, is_wasd: bool) !GameInstance {
        const WIDTH: usize = 60;
        const HEIGHT: usize = 30;
        const FPS: f64 = 60;

        // Create engine with different colors for each client
        var engine = if (is_wasd)
            try Engine.Engine.init(allocator, WIDTH, HEIGHT, FPS, Engine.Color{ .r = 20, .g = 20, .b = 40 })
        else
            try Engine.Engine.init(allocator, WIDTH, HEIGHT, FPS, Engine.Color{ .r = 40, .g = 20, .b = 20 });

        // Create player
        const player = if (is_wasd)
            try Player.createWASDPlayer(allocator, 30, 15)
        else
            try createVimPlayer(allocator, 30, 15);

        return GameInstance{
            .engine = engine,
            .player = player,
            .client_id = client_id,
            .is_running = false,
            .thread_handle = null,
            .mutex = Mutex{},
            .process_handle = null,
        };
    }

    pub fn deinit(self: *GameInstance) void {
        self.mutex.lock();
        self.is_running = false;
        self.mutex.unlock();

        if (self.thread_handle) |handle| {
            handle.join();
        }

        if (self.process_handle) |*handle| {
            _ = handle.kill() catch {};
        }

        self.player.deinit();
        self.engine.deinit();
    }

    pub fn startInNewTerminal(self: *GameInstance, allocator: std.mem.Allocator) !void {
        std.debug.print("Attempting to start instance {d} in new terminal\n", .{self.client_id});

        self.process_handle = TerminalSpawner.spawnInNewTerminal(allocator, self.client_id, self.player.entity.ch == '@') catch |err| switch (err) {
            error.NoTerminalFound => {
                std.debug.print("Starting instance {d} in current terminal (no separate terminal available)\n", .{self.client_id});
                try self.start();
                return;
            },
            else => {
                std.debug.print("Error spawning terminal for instance {d}: {any}\n", .{ self.client_id, err });
                return err;
            },
        };

        std.debug.print("Started instance {d} in new terminal session\n", .{self.client_id});
    }

    pub fn start(self: *GameInstance) !void {
        self.mutex.lock();
        self.is_running = true;
        self.mutex.unlock();

        self.thread_handle = try Thread.spawn(.{}, gameLoop, .{self});
    }

    pub fn runStandalone(self: *GameInstance) !void {
        std.debug.print("Running standalone game instance {d}\n", .{self.client_id});

        current_instance = self;

        const UpdateFunctions = struct {
            fn update() void {
                if (current_instance) |instance| {
                    // Clear canvas
                    instance.engine.canvas.clear(' ', instance.engine.background_color);

                    // Draw player
                    instance.player.draw(&instance.engine.canvas);

                    // Draw UI
                    drawInstanceUI(&instance.engine, instance);
                }
            }
        };

        self.engine.setUpdateFn(&UpdateFunctions.update);

        // Simulate some movement for demo
        const input_thread = try Thread.spawn(.{}, simulateInput, .{self});
        defer input_thread.join();

        // Run the engine loop (this blocks)
        try self.engine.run();
    }

    fn gameLoop(self: *GameInstance) void {
        current_instance = self;

        const UpdateFunctions = struct {
            fn update() void {
                if (current_instance) |instance| {
                    instance.mutex.lock();
                    defer instance.mutex.unlock();

                    instance.engine.canvas.clear(' ', instance.engine.background_color);
                    instance.player.draw(&instance.engine.canvas);
                    drawInstanceUI(&instance.engine, instance);
                }
            }
        };

        self.engine.setUpdateFn(&UpdateFunctions.update);

        self.engine.run() catch |err| {
            std.debug.print("Engine error for instance {d}: {any}\n", .{ self.client_id, err });
        };
    }

    pub fn processInput(self: *GameInstance, input: u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const action = self.player.processInput(input);
        switch (action) {
            .UP => {
                if (self.player.entity.y > 0) self.player.move(0, -1);
            },
            .DOWN => {
                if (self.player.entity.y < 28) self.player.move(0, 1);
            },
            .LEFT => {
                if (self.player.entity.x > 0) self.player.move(-1, 0);
            },
            .RIGHT => {
                if (self.player.entity.x < 58) self.player.move(1, 0);
            },
            else => {},
        }
    }
};

const GameServer = struct {
    instances: std.ArrayList(*GameInstance),
    server_engine: Engine.Engine,
    allocator: std.mem.Allocator,
    mutex: Mutex,
    next_client_id: u32,
    child_processes: std.ArrayList(process.Child),

    pub fn init(allocator: std.mem.Allocator) !GameServer {
        var server_engine = try Engine.Engine.init(allocator, 80, 30, 30, Engine.Color{ .r = 10, .g = 10, .b = 10 });

        return GameServer{
            .instances = std.ArrayList(*GameInstance).init(allocator),
            .server_engine = server_engine,
            .allocator = allocator,
            .mutex = Mutex{},
            .next_client_id = 0,
            .child_processes = std.ArrayList(process.Child).init(allocator),
        };
    }

    pub fn deinit(self: *GameServer) void {
        for (self.child_processes.items) |*child| {
            _ = child.kill() catch {};
        }
        self.child_processes.deinit();

        for (self.instances.items) |instance| {
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

        current_server = self;

        const UpdateFunctions = struct {
            fn update() void {
                if (current_server) |server| {
                    server.mutex.lock();
                    defer server.mutex.unlock();

                    server.server_engine.canvas.clear(' ', server.server_engine.background_color);
                    drawServerOverview(&server.server_engine, server);
                }
            }
        };

        self.server_engine.setUpdateFn(&UpdateFunctions.update);
        try self.server_engine.run();
    }
};

fn createVimPlayer(allocator: std.mem.Allocator, start_x: i32, start_y: i32) !Player.Player {
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

    const is_wasd = instance.player.entity.ch == '@';
    const color = if (is_wasd) yellow else cyan;
    const controls = if (is_wasd) "WASD Controls - Dedicated Terminal" else "HJKL Controls - Dedicated Terminal";

    // Draw title
    for (controls, 0..) |char, i| {
        if (i >= 58) break;
        engine.canvas.put(@intCast(i), 0, char);
        engine.canvas.fillColor(@intCast(i), 0, color);
    }

    // Draw client info
    const client_info = std.fmt.allocPrint(std.heap.page_allocator, "Client {d} - Standalone Session", .{instance.client_id}) catch return;
    defer std.heap.page_allocator.free(client_info);

    for (client_info, 0..) |char, i| {
        if (i >= 58) break;
        engine.canvas.put(@intCast(i), 1, char);
        engine.canvas.fillColor(@intCast(i), 1, white);
    }

    // Draw player position
    const pos = instance.player.getPosition();
    const pos_text = std.fmt.allocPrint(std.heap.page_allocator, "Position: ({d}, {d})", .{ pos.x, pos.y }) catch return;
    defer std.heap.page_allocator.free(pos_text);

    for (pos_text, 0..) |char, i| {
        if (i >= 58) break;
        engine.canvas.put(@intCast(i), 27, char);
        engine.canvas.fillColor(@intCast(i), 27, white);
    }

    // Draw border
    for (0..60) |x| {
        engine.canvas.put(@intCast(x), 2, '-');
        engine.canvas.fillColor(@intCast(x), 2, color);
    }
}

fn drawServerOverview(engine: *Engine.Engine, server: *GameServer) void {
    const white = Engine.Color{ .r = 255, .g = 255, .b = 255 };
    const green = Engine.Color{ .r = 0, .g = 255, .b = 0 };
    const blue = Engine.Color{ .r = 100, .g = 150, .b = 255 };

    // Server title
    const title = "MULTI-TERMINAL GAME SERVER";
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
    const instance_text = std.fmt.allocPrint(std.heap.page_allocator, "Active Terminal Sessions: {d}", .{server.instances.items.len}) catch return;
    defer std.heap.page_allocator.free(instance_text);

    for (instance_text, 0..) |char, i| {
        engine.canvas.put(@intCast(i + 5), 7, char);
        engine.canvas.fillColor(@intCast(i + 5), 7, blue);
    }

    // List running instances
    var y_offset: i32 = 10;
    for (server.instances.items) |instance| {
        if (y_offset >= 20) break;

        const is_wasd = instance.player.entity.ch == '@';
        const status_text = std.fmt.allocPrint(std.heap.page_allocator, "Terminal {d}: {s} Controls - Separate Process", .{ instance.client_id, if (is_wasd) "WASD" else "HJKL" }) catch continue;
        defer std.heap.page_allocator.free(status_text);

        for (status_text, 0..) |char, j| {
            if (j >= 75) break;
            engine.canvas.put(@intCast(j + 5), y_offset, char);
            engine.canvas.fillColor(@intCast(j + 5), y_offset, green);
        }

        y_offset += 1;
    }

    // Instructions
    const instructions = [_][]const u8{
        "Press 'q' to quit server and close all terminals",
        "Each client runs in its own terminal window",
        "No screen tearing - independent rendering",
    };

    y_offset = 22;
    for (instructions) |instruction| {
        if (y_offset >= 30) break;

        for (instruction, 0..) |char, i| {
            if (i >= 75) break;
            engine.canvas.put(@intCast(i + 2), y_offset, char);
            engine.canvas.fillColor(@intCast(i + 2), y_offset, white);
        }
        y_offset += 1;
    }
}

fn simulateInput(instance: *GameInstance) void {
    const input_sequence = if (instance.player.entity.ch == '@') "wwwwssssaaaadddwwww" else "kkkkjjjjhhhhllllkkkk";

    std.debug.print("Simulating input for client {d}\n", .{instance.client_id});

    for (input_sequence) |input| {
        instance.processInput(input);
        std.time.sleep(300_000_000); // 300ms delay
    }
}

fn parseArgs(allocator: std.mem.Allocator) !struct { client_mode: bool, client_id: u32, is_wasd: bool } {
    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    var client_mode = false;
    var client_id: u32 = 0;
    var is_wasd = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--client-mode")) {
            client_mode = true;
        } else if (std.mem.startsWith(u8, args[i], "--client-id=")) {
            const id_str = args[i][12..];
            client_id = try std.fmt.parseInt(u32, id_str, 10);
        } else if (std.mem.startsWith(u8, args[i], "--is-wasd=")) {
            const wasd_str = args[i][10..];
            is_wasd = std.mem.eql(u8, wasd_str, "true");
        }
    }

    return .{ .client_mode = client_mode, .client_id = client_id, .is_wasd = is_wasd };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try parseArgs(allocator);

    // If running in client mode, start a single game instance
    if (args.client_mode) {
        std.debug.print("Starting client instance {d} ({s})\n", .{ args.client_id, if (args.is_wasd) "WASD" else "HJKL" });

        var instance = try GameInstance.init(allocator, args.client_id, args.is_wasd);
        defer instance.deinit();

        try instance.runStandalone();
        return;
    }

    // Otherwise, run as server
    std.debug.print("Starting Multi-Terminal Game Server\n", .{});
    std.debug.print("Available CPU cores: {d}\n", .{Thread.getCpuCount() catch 1});

    var server = try GameServer.init(allocator);
    defer server.deinit();

    // Create game instances
    const instance1 = try server.createInstance(true); // WASD player
    const instance2 = try server.createInstance(false); // HJKL player

    // Start instances in new terminal sessions
    std.debug.print("Creating first terminal session...\n", .{});
    try instance1.startInNewTerminal(allocator);
    std.time.sleep(2_000_000_000); // 2 second delay

    std.debug.print("Creating second terminal session...\n", .{});
    try instance2.startInNewTerminal(allocator);
    std.time.sleep(2_000_000_000); // 2 second delay

    std.debug.print("Game instances created. Starting server coordination interface...\n", .{});
    std.debug.print("Note: If terminals didn't spawn, check the debug output above.\n", .{});
    std.debug.print("Server will run until you press 'q'\n", .{});

    // Start server master engine (this will block until exit)
    try server.startServerEngine();

    std.debug.print("Multi-Terminal Game Server terminated\n", .{});
}

pub fn setInput(input: u8) void {
    _ = input;
}
