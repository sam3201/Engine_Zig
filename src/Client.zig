//src/Client.zig

const std = @import("std");
const net = std.net;
const eng = @import("Engine.zig");
const PlayerModule = @import("Player.zig");
const Chunk = @import("Chunk.zig");

var g_stream: ?*net.Stream = null;
var g_read_buf: [4096]u8 = undefined;
var g_write_buf: [1024]u8 = undefined;
var g_allocator: ?std.mem.Allocator = null;
var g_reader: ?*net.Stream.Reader = null;

fn readLineAlloc(allocator: std.mem.Allocator, reader: std.net.Stream.Reader, max_len: usize) ![]u8 {
    var line_writer = std.io.Writer.Allocating.init(allocator);
    defer line_writer.deinit();

    while (true) {
        var buf: [1]u8 = undefined;
        const len = try reader.read(&buf);
        if (len == 0) break;
        _ = try line_writer.writer.write(&buf);         
    } 

    const line = line_writer.written();
    if (line.len > max_len) return error.StreamTooLong;

    return try allocator.dupe(u8, line);
}

pub fn connectToServer() !net.Stream {
    const address = try net.Address.parseIp("127.0.0.1", 42069);
    const stream = try net.tcpConnectToAddress(address);
    std.debug.print("Connected to server\n", .{});
    return stream;
}

pub fn disconnectFromServer(stream: *net.Stream) void {
    stream.close();
    std.debug.print("Disconnected from server\n", .{});
}

pub fn sendInput(stream: *net.Stream, input_data: []const u8) !void {
    try stream.writeAll(input_data);
}

pub fn renderGameState(
    allocator: std.mem.Allocator,
    reader: net.Stream.Reader,
    canvas: *eng.Canvas,
) !void {
    canvas.clear(' ', eng.Color{ .r = 0, .g = 0, .b = 0 });

    while (true) {
        const line = try readLineAlloc(allocator, reader, 1024);

        defer allocator.free(line);

        if (std.mem.eql(u8, line, "END")) break;

        var it = std.mem.splitScalar(u8, line, ' ');
        const label = it.next() orelse continue;

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
        }
    }
}

pub fn update(canvas: *eng.Canvas) void {
    const input = eng.readKey() catch null;

    if (input) |key| {
        if (g_stream) |s| {
            var buf: [1]u8 = .{key};
            _ = sendInput(s, &buf) catch {};
        }
    }

    if (g_stream) |s| {
        if (g_allocator) |alloc| {
            const reader = s.reader(&g_read_buf);
            _ = renderGameState(alloc, reader, canvas);
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try eng.Engine.init(allocator, 80, 24, 60, eng.Color{ .r = 0, .g = 0, .b = 0 });
    defer engine.deinit();

    var stream = try connectToServer();
    g_stream = &stream;
    g_allocator = allocator;
    var reader_struct = stream.reader(&g_read_buf);
    g_reader = &reader_struct;

    defer disconnectFromServer(&stream);

    engine.canvas.setUpdateFn(update);

    try engine.run();
}
