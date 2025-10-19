const std = @import("std");
const posix = std.posix;
const net = std.net;
const Engine = @import("Engine.zig");

// FIX: Define a named struct for player positions to resolve the type mismatch error.
const PlayerPosition = struct { x: i32, y: i32 };

// Global state for the client
var g_socket: ?posix.socket_t = null;
var g_read_buffer: [8192]u8 = undefined;
// FIX: Use the named PlayerPosition struct here.
var g_player_positions: std.AutoHashMap(u32, PlayerPosition) = undefined;

pub fn connectToServer(allocator: std.mem.Allocator) !void {
    // FIX: And use the named PlayerPosition struct here for initialization.
    g_player_positions = std.AutoHashMap(u32, PlayerPosition).init(allocator);
    const address = try net.Address.parseIp("127.0.0.1", 42069);
    const socket = try posix.socket(address.any.family, posix.SOCK.STREAM, 0);

    try posix.connect(socket, &address.any, address.getOsSockLen());
    g_socket = socket;
    std.debug.print("Connected to server\n", .{});
}

pub fn disconnectFromServer() void {
    if (g_socket) |socket| {
        posix.close(socket);
        g_socket = null;
        g_player_positions.deinit();
        std.debug.print("Disconnected from server\n", .{});
    }
}

fn sendInput(key: u8) !void {
    if (g_socket) |socket| {
        const buf = [_]u8{key};
        _ = try posix.write(socket, &buf);
    }
}

fn parseState(data: []const u8) !void {
    var line_iterator = std.mem.splitScalar(u8, data, '\n');
    while (line_iterator.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, "END")) break;

        var parts = std.mem.splitScalar(u8, line, ' ');
        const label = parts.next() orelse continue;

        if (std.mem.eql(u8, label, "Player")) {
            const id_str = parts.next() orelse continue;
            const x_str = parts.next() orelse continue;
            const y_str = parts.next() orelse continue;

            const id = try std.fmt.parseInt(u32, id_str, 10);
            const x = try std.fmt.parseInt(i32, x_str, 10);
            const y = try std.fmt.parseInt(i32, y_str, 10);

            try g_player_positions.put(id, .{ .x = x, .y = y });
        }
    }
}

// This function is set as the callback for the engine's game loop.
pub fn updateAndRender(canvas: *Engine.Canvas) void {
    if (g_socket == null) return;
    const socket = g_socket.?;

    // 1. Handle input and send to server
    if (Engine.readKey() catch null) |key| {
        if (key == 'q' or key == 27) return;
        sendInput(key) catch {};
    }

    // 2. Receive world state
    const bytes_read = posix.read(socket, &g_read_buffer) catch |err| {
        if (err != error.WouldBlock) return;
        disconnectFromServer();
        return;
    };

    if (bytes_read > 0) {
        parseState(g_read_buffer[0..bytes_read]) catch |err| {
            std.debug.print("Parse error: {any}\n", .{err});
            return;
        };
    }

    // 3. Render state (just mirror players)
    canvas.clear(' ', .{ .r = 10, .g = 10, .b = 10 });
    var it = g_player_positions.iterator();
    while (it.next()) |entry| {
        const p = entry.value_ptr;
        canvas.put(p.x, p.y, '@');
        canvas.fillColor(p.x, p.y, .{ .r = 255, .g = 255, .b = 0 });
    }
}
// The main game loop for a client, called from main.zig
pub fn runClient(allocator: std.mem.Allocator, engine: *Engine.Engine) !void {
    try connectToServer(allocator);
    defer disconnectFromServer();

    engine.canvas.setUpdateFn(updateAndRender);
    try engine.run();
}

// Dummy main for build system
pub fn main() !void {}


