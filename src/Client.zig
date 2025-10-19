const std = @import("std");
const posix = std.posix;
const net = std.net;
const eng = @import("Engine.zig");

const GameState = struct {
    players: std.StringHashMap(*const PlayerRenderInfo),
    allocator: std.mem.Allocator,

    const PlayerRenderInfo = struct {
        x: i32,
        y: i32,
        ch: u8,
    };

    pub fn init(allocator: std.mem.Allocator) GameState {
        return .{
            .allocator = allocator,
            .players = std.StringHashMap(*const PlayerRenderInfo).init(allocator),
        };
    }

    pub fn deinit(self: *GameState) void {
        var it = self.players.valueIterator();
        while (it.next()) |player_info| {
            self.allocator.destroy(player_info);
        }
        self.players.deinit();
    }
};

var g_socket: ?posix.socket_t = null;
var g_game_state: ?*GameState = null;

pub fn connectToServer(allocator: std.mem.Allocator) !void {
    const address = try net.Address.parseIp("127.0.0.1", 42069);
    const socket = try posix.socket(address.any.family, .STREAM, 0);
    try posix.connect(socket, &address.any, address.getOsSockLen());
    g_socket = socket;

    g_game_state = try allocator.create(GameState);
    g_game_state.?.* = GameState.init(allocator);

    std.debug.print("Connected to server\n", .{});
}

pub fn disconnectFromServer() void {
    if (g_socket) |socket| {
        posix.close(socket);
        g_socket = null;
        if (g_game_state) |state| {
            state.deinit();
            std.heap.page_allocator.destroy(state);
            g_game_state = null;
        }
        std.debug.print("Disconnected from server\n", .{});
    }
}

pub fn sendInput(key: u8) !void {
    if (g_socket) |socket| {
        const buf = [_]u8{key};
        _ = try posix.write(socket, &buf);
    }
}

fn parseAndUpdateState(data: []const u8) !void {
    if (g_game_state == null) return;
    const state = g_game_state.?;

    var line_iterator = std.mem.splitScalar(u8, data, '\n');
    while (line_iterator.next()) |line| {
        if (std.mem.eql(u8, line, "END")) break;

        var parts = std.mem.splitScalar(u8, line, ' ');
        const label = parts.next() orelse continue;

        if (std.mem.eql(u8, label, "Player")) {
            const id_str = parts.next() orelse continue;
            const x_str = parts.next() orelse continue;
            const y_str = parts.next() orelse continue;

            const x = try std.fmt.parseInt(i32, x_str, 10);
            const y = try std.fmt.parseInt(i32, y_str, 10);

            if (state.players.get(id_str)) |player_info| {
                player_info.x = x;
                player_info.y = y;
            } else {
                const new_info = try state.allocator.create(GameState.PlayerRenderInfo);
                new_info.* = .{ .x = x, .y = y, .ch = '@' };
                try state.players.put(id_str, new_info);
            }
        }
    }
}

pub fn updateAndRender(canvas: *eng.Canvas) void {
    if (g_socket == null) return;

    if (eng.readKey() catch null) |key| {
        sendInput(key) catch {};
    }

    var read_buffer: [4096]u8 = undefined;
    const bytes_read = posix.read(g_socket.?, &read_buffer) catch |err| {
        if (err == error.WouldBlock) {
            // No new data, just render old state
        } else {
            disconnectFromServer();
            return;
        }
        return 0;
    };

    if (bytes_read > 0) {
        parseAndUpdateState(read_buffer[0..bytes_read]) catch {};
    }

    // 3. Render
    canvas.clear(' ', .{});
    if (g_game_state) |state| {
        var it = state.players.valueIterator();
        while (it.next()) |player_info| {
            canvas.put(player_info.x, player_info.y, player_info.ch);
            canvas.fillColor(player_info.x, player_info.y, .{ .r = 255, .g = 255, .b = 0 });
        }
    }
}


