const std = @import("std");
const Server = @import("Server.zig");
const Client = @import("Client.zig");
const Engine = @import("Engine.zig").Engine;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const GameServer = Server.GameServer.init(allocator); 

    if (args.len >= 2 and std.mem.eql(u8, args[1], "server")) {
        var server = try Server.GameServer.init(allocator);
        defer server.deinit();

    } else if (args.len >= 2 and std.mem.eql(u8, args[1], "client")) {
        var client = Client.init(allocator);
        try client.connect("127.0.0.1", 42069);

        var engine = try Engine.init(allocator, 80, 40, 30, .{ .r = 0, .g = 0, .b = 0 });
        defer engine.deinit();

        while (true) {
            client.updateAndRender(&engine.canvas);
            try engine.canvas.flushToTerminal();
        }
    } else {
        std.debug.print("Usage: ./Engine server | ./Engine client\n", .{});
    }
}

