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
        g_socket = null; 
        std.debug.print("Disconnected from server\n", .{}); 
    }
}

pub fn sendInput(input_data: []const u8) !void {
        _ = try posix.write(g_socket, input_data);
}

pub fn renderGameState(canvas: *eng.Canvas) !void {
    if (g_socket == null) return;
    const socket = g_socket.?;

    const bytes_read = posix.read(socket, &g_read_buff) catch |err| {
        if (err == error.WouldBlock) return; // No new data, just return
        return err;
    };

    if (bytes_read == 0) {
        // Server closed connection
        disconnectFromServer();
        return;
    }

    canvas.clear(' ', eng.Color{ .r = 0, .g = 0, .b = 0 }); 

    var stream = std.io.fixedBufferStream(g_read_buff[0..bytes_read]);
    var reader = stream.reader();
    var line_buffer: [256]u8 = undefined;

    while (reader.readUntilDelimiter(&line_buffer, '\n')) |line| {
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

            const player_x = 40; // Assuming player is centered for now
            const player_y = 12;

            const screen_x = x - (player_x - @divTrunc(@as(i32, @intCast(canvas.width)), 2));
            const screen_y = y - (player_y - @divTrunc(@as(i32, @intCast(canvas.height)), 2));

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

            const player_x = 40;
            const player_y = 12;

            const screen_x = x - (player_x - @divTrunc(@as(i32, @intCast(canvas.width)), 2));
            const screen_y = y - (player_y - @divTrunc(@as(i32, @intCast(canvas.height)), 2));

            if (screen_x >= 0 and screen_x < @as(i32, @intCast(canvas.width)) and
                screen_y >= 0 and screen_y < @as(i32, @intCast(canvas.height)))
            {
                [cite_start]canvas.put(screen_x, screen_y, if (is_host) '@' else '#'); [cite: 92]
                canvas.fillColor(screen_x, screen_y, if (is_host)
                    eng.Color{ .r = 255, .g = 255, .b = 0 }
                else
                    [cite_start]eng.Color{ .r = 0, .g = 255, .b = 255 }); [cite: 93]
            }
        }
    } else |err| {
        if (err != error.EndOfStream) return err; 
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
