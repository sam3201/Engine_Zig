const std = @import("std");
const posix = std.posix;
const net = std.net;
const eng = @import("Engine.zig");
const Chunk = @import("Chunk.zig");

var g_socket: ?posix.socket_t = null;
var g_read_buffer: [8192]u8 = undefined;
var g_player_positions = std.AutoHashMap(u32, struct { x: i32, y: i32 }).init(std.heap.page_allocator);

pub fn connectToServer(allocator: std.mem.Allocator) !void {
    _ = allocator;
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

pub fn sendInput(key: u8) !void {
    if (g_socket) |socket| {
        const buf = [_]u8{key};
        _ = try posix.write(socket, &buf);
    }
}

fn parseState(data: []const u8) !void {
    var line_iterator = std.mem.splitScalar(u8, data, '\n');
    while (line_iterator.next()) |line| {
        if (line.len == 0 or std.mem.eql(u8, line, "END")) continue;

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

pub fn updateAndRender(canvas: *eng.Canvas) void {
    if (g_socket == null) return;
    const socket = g_socket.?;

    // Send input if any
    if (eng.readKey() catch null) |key| {
        sendInput(key) catch {};
    }

    const bytes_read = posix.read(socket, &g_read_buffer) catch |err| {
        std.debug.print("Read error: {any}\n", .{err});
        disconnectFromServer();
        return;
    };
    if (bytes_read > 0) {
        parseState(g_read_buffer[0..bytes_read]) catch |err| {
            std.debug.print("Parse error: {any}\n", .{err});
        };
    }
    };

    // Render the current known state
    canvas.clear(' ', .{});
    var it = g_player_positions.iterator();
    while (it.next()) |entry| {
        canvas.put(entry.value_ptr.x, entry.value_ptr.y, '@');
        canvas.fillColor(entry.value_ptr.x, entry.value_ptr.y, .{ .r = 255, .g = 255, .b = 0 });
    }
}

// FIX 2: Add a main function so the compiler does not error when compiling this as an executable root.
pub fn main() !void {
    // This file is intended to be used as a module and is not the actual entry point.
    // The main entry point is expected in main.zig
}

