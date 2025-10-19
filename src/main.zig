const std = @import("std");
const Server = @import("Server.zig");
const Client = @import("Client.zig");
const Engine = @import("Engine.zig").Engine;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len >= 2 and std.mem.eql(u8, args[1], "server")) {
        const GameServer = Server.GameServer;
        try GameServer.init(allocator);
        defer GameServer.deinit();

        GameServer.startServer();

    } else if (args.len >= 2 and std.mem.eql(u8, args[1], "client")) {
        const client = Client.Client.init(allocator); 
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

