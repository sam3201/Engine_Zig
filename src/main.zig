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
        try GameServer.init(allocator) catch |err| {
            std.debug.print("Error: {s}\n", .{err});            
        };
        defer GameServer.deinit();

        GameServer.startServer();

    } else if (args.len >= 2 and std.mem.eql(u8, args[1], "client")) {
        try Client.connectToServer(allocator); 

    } else {
        std.debug.print("Usage: ./Engine server | ./Engine client\n", .{});
    }
}

