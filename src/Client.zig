// src/Client.zig

const std = @import("std");
const net = std.net;
const eng = @import("Engine.zig");
const PlayerModule = @import("Player.zig");
const Chunk = @import("Chunk.zig");

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
    const writer = stream.writer();
    try writer.writeAll(input_data);
    try writer.writeAll("\n");
}

pub fn renderGameState(
    stream: *net.Stream,
    allocator: std.mem.Allocator,
    canvas: *eng.Canvas,
) !void {
    const reader = stream.reader();

    canvas.clear(' ', eng.Color{ .r = 0, .g = 0, .b = 0 });

    while (true) {
        const line = try reader.readUntilDelimiterAlloc(allocator, '\n', 1024);
        defer allocator.free(line);

        if (std.mem.eql(u8, line, "END")) break;

        var it = std.mem.splitAny(u8, line, " ");
        const label = it.next() orelse continue;

        if (std.mem.eql(u8, label, "Tile")) {
            const x_str = it.next() orelse continue;
            const y_str = it.next() orelse continue;
            const tile_type_str = it.next() orelse continue;

            const x = try std.fmt.parseInt(i32, x_str, 10);
            const y = try std.fmt.parseInt(i32, y_str, 10);
            const tile_type_int = try std.fmt.parseInt(usize, tile_type_str, 10);
            const tile_type = @as(Chunk.TileType, @enumFromInt(tile_type_int));

            // Adjust for camera (center on host player)
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

            // Adjust for camera
            const camera_x = x - @divTrunc(@as(i32, @intCast(canvas.width)), 2);
            const camera_y = y - @divTrunc(@as(i32, @intCast(canvas.height)), 2);
            const screen_x = x - camera_x;
            const screen_y = y - camera_y;

            if (screen_x >= 0 and screen_x < @as(i32, @intCast(canvas.width)) and
                screen_y >= 0 and screen_y < @as(i32, @intCast(canvas.height)))
            {
                canvas.put(screen_x, screen_y, if (is_host) '@' else '#');
                canvas.fillColor(screen_x, screen_y, if (is_host) eng.Color{ .r = 255, .g = 255, .b = 0 } else eng.Color{ .r = 0, .g = 255, .b = 255 });
            }
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
    defer disconnectFromServer(&stream);

    const UpdateContext = struct {
        stream_ptr: *net.Stream,
        allocator: std.mem.Allocator,

        pub fn update(self: *@This(), canvas: *eng.Canvas) void {
            // Try to send input if any
            const input = eng.readKey() catch 0;
            if (input != 0) {
                var buf: [1]u8 = .{input};
                _ = sendInput(self.stream_ptr, &buf) catch {};
            }

            // Try to update game state
            _ = renderGameState(self.stream_ptr, self.allocator, canvas) catch {};
        }
    };

    var context = UpdateContext{
        .stream_ptr = &stream,
        .allocator = allocator,
    };

    engine.canvas.setUpdateFn(&context.update);
    try engine.run();
}

