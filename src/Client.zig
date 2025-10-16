//src/Client.zig


const std = @import("std");
const posix = std.posix; 
const net = std.net;
const eng = @import("Engine.zig");
const Chunk = @import("Chunk.zig");

var g_socket: ?posix.socket_t = null; 
var g_read_buff: [8192]u8 = undefined; 

pub fn connectToServer() !void {
    const address = try net.Address.parseIp("127.0.0.1", 42069); 

    const socket = try posix.socket(address.any.family, posix.SOCK.STREAM, 0);
    try posix.connect(socket, &address.any, address.getOsSockLen());

    g_socket = socket;

    std.debug.print("Connected to server\n", .{}); 
}

pub fn disconnectFromServer() void {
    if (g_socket) |socket| {
        posix.close(socket);
        [cite_start]g_socket = null; 
        [cite_start]std.debug.print("Disconnected from server\n", .{}); 
    }
}

pub fn sendInput(input_data: []const u8) !void {
    try g_stream_writer.writeAll(input_data);
    try g_stream_writer.flush();
}

pub fn renderGameState(canvas: *eng.Canvas) !void {
    canvas.clear(' ', eng.Color{ .r = 0, .g = 0, .b = 0 });


    while (io_reader.takeDelimiterExclusive(&line_buffer, '\n')) |_| {
        const line = line_buffer.items;
        var it = std.mem.splitScalar(u8, line, ' ');
        const label = it.next() orelse continue;

        if (std.mem.eql(u8, label, "END")) break;

        if (std.mem.eql(u8, label, "Tile")) {
            const x_str = it.next() orelse continue;
            const y_str = it.next() orelse continue;
            const tile_type_str = it.next() orelse continue;

            const x = try std.fmt.parseInt(i32, x_str, 10);
            const y = try std.fmt.parseInt(i32, y_str, 10);
            const tile_type_int = try std.fmt.parseInt(usize, tile_type_str, 10);
            const tile_type = @as(Chunk.TileType, @enumFromInt(tile_type_int));

            const camera_x = x - @divTrunc(@as(i32, @intCast(canvas.width)), 2);
            const camera_y = y - @divTrunc(@as(i32, @intCast(canvas.height)), 2);
            const screen_x = x - camera_x;
            const screen_y = y - camera_y;

            if (screen_x >= 0 and screen_x < @as(i32, @intCast(canvas.width)) and
                screen_y >= 0 and screen_y < @as(i32, @intCast(canvas.height)))
            {
                canvas.put(screen_x, screen_y, tile_type.getChar());
                canvas.fillColor(screen_x, screen_y, tile_type.getColor());
            }
        } else if (std.mem.eql(u8, label, "Player")) {
            const x_str = it.next() orelse continue;
            const y_str = it.next() orelse continue;
            const is_host_str = it.next() orelse continue;

            const x = try std.fmt.parseInt(i32, x_str, 10);
            const y = try std.fmt.parseInt(i32, y_str, 10);
            const is_host = std.mem.eql(u8, is_host_str, "true");

            const camera_x = x - @divTrunc(@as(i32, @intCast(canvas.width)), 2);
            const camera_y = y - @divTrunc(@as(i32, @intCast(canvas.height)), 2);
            const screen_x = x - camera_x;
            const screen_y = y - camera_y;

            if (screen_x >= 0 and screen_x < @as(i32, @intCast(canvas.width)) and
                screen_y >= 0 and screen_y < @as(i32, @intCast(canvas.height)))
            {
                canvas.put(screen_x, screen_y, if (is_host) '@' else '#');
                canvas.fillColor(screen_x, screen_y, if (is_host)
                    eng.Color{ .r = 255, .g = 255, .b = 0 }
                else
                    eng.Color{ .r = 0, .g = 255, .b = 255 });
            }
            line_buffer.clearAndFree();
        } else |err| {
            if (err != error.EndOfStream) return err;
        }
    }
}

pub fn update(canvas: *eng.Canvas) void {
    const input = eng.readKey() catch null;

    if (input) |key| {
        var buf: [2]u8 = .{ key, '\n' };
        _ = sendInput(&buf) catch {};
    }

    _ = renderGameState(canvas) catch {};
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try eng.Engine.init(allocator, 80, 24, 60, eng.Color{ .r = 0, .g = 0, .b = 0 });
    defer engine.deinit();

    try connectToServer();

    defer disconnectFromServer();

    engine.canvas.setUpdateFn(update);

    try engine.run();
}
