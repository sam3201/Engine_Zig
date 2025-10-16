const std = @import("std");
const net = std.net;
const eng = @import("Engine.zig");
const Chunk = @import("Chunk.zig");

// Use optional types to represent nullable global variables.
var g_stream: ?net.Stream = null;

// The buffered reader itself holds the state and a buffer.
// Declare it as an optional struct, not just a pointer.
var g_stream_reader: ?net.Stream.Reader = null;
const read_buff_max = 4096;
var g_read_buff: [read_buff_max]u8 = undefined;

var g_stream_writer: ?net.Stream.Writer = null;
const write_buff_max = 4096;
var g_write_buff: [write_buff_max]u8 = undefined;

var g_allocator: ?std.mem.Allocator = null;

pub fn connectToServer() !void {
    const address = try net.Address.parseIp("127.0.0.1", 42069);
    g_stream = try net.tcpConnectToAddress(address);

    // Initialize the buffered reader with the stream and the buffer.
    g_stream_reader = g_stream.?.reader(&g_read_buff);

    // Initialize the buffered writer.
    g_stream_writer = g_stream.?.writer(&g_write_buff);

    std.debug.print("Connected to server\n", .{});
}

pub fn disconnectFromServer() void {
    if (g_stream) |*stream| {
        stream.close();
        g_stream = null;
        std.debug.print("Disconnected from server\n", .{});
    }
}

pub fn sendInput(input_data: []const u8) !void {
    // Write using the buffered writer interface.
    if (g_stream_writer) |*writer| {
        try writer.interface().writeAll(input_data);
        try writer.flush();
    }
}

pub fn renderGameState(canvas: *eng.Canvas) !void {
    canvas.clear(' ', eng.Color{ .r = 0, .g = 0, .b = 0 });

    if (g_allocator == null or g_stream_reader == null) {
        return;
    }

    const allocator = g_allocator.?;
    const io_reader = g_stream_reader.?.interface();

    var line_buffer = std.ArrayList(u8).init(allocator);
    defer line_buffer.deinit();

    // Use a while loop with `takeDelimiterExclusive` to read lines.
    while (io_reader.takeDelimiterExclusive(&line_buffer, '\n')) |_| {
        const line = line_buffer.items;
        var it = std.mem.splitScalar(u8, line, ' ');
        const label = it.next() orelse continue;

        if (std.mem.eql(u8, label, "END")) break;

        if (std.mem.eql(u8, label, "Tile")) {
            // ... (rest of the logic is correct)
        } else if (std.mem.eql(u8, label, "Player")) {
            // ... (rest of the logic is correct)
        }
        line_buffer.clearAndFree();
    } else |err| {
        if (err != error.EndOfStream) {
            return err;
        }
    }
}

pub fn update(canvas: *eng.Canvas) void {
    const input = eng.readKey() catch null;

    if (input) |key| {
        var buf: [2]u8 = .{ key, '\n' };
        _ = sendInput(&buf) catch {};
    }

    if (g_stream and g_allocator) {
        _ = renderGameState(canvas) catch {};
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var engine = try eng.Engine.init(allocator, 80, 24, 60, eng.Color{ .r = 0, .g = 0, .b = 0 });
    defer engine.deinit();

    try connectToServer();
    g_allocator = allocator;

    defer disconnectFromServer();

    engine.canvas.setUpdateFn(update);

    try engine.run();
}
