const std = @import("std");
const net = std.net;
const json = std.json;
const posix = std.posix;
const eng = @import("Engine.zig");

const PlayerState = struct {
    id: u32,
    x: i32,
    y: i32,
    hp: i32,
};

const GameState = struct {
    tick: u64,
    players: []PlayerState,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    fd: posix.fd_t,
    game_state: GameState,
    connected: bool,

    pub fn connect(allocator: std.mem.Allocator, host: []const u8, port: u16) !Client {
        const address = try net.Address.parseIp4(host, port);
        const stream = try net.tcpConnectToAddress(address);

        std.debug.print("Connected to {s}:{d}\n", .{ host, port });

        return .{
            .allocator = allocator,
            .fd = stream.handle,
            .game_state = .{ .tick = 0, .players = &[_]PlayerState{} },
            .connected = true,
        };
    }

    pub fn deinit(self: *Client) void {
        posix.close(self.fd);
    }

    pub fn send(self: *Client, msg: []const u8) void {
        _ = posix.write(self.fd, msg) catch {};
    }

    pub fn receive(self: *Client) void {
        var buf: [2048]u8 = undefined;
        const len = posix.read(self.fd, &buf) catch return;
        if (len == 0) return;

        const parsed = json.parseFromSlice(GameState, self.allocator, buf[0..len], .{}) catch return;
        defer parsed.deinit();
        self.game_state = parsed.value;
    }

    pub fn draw(self: *Client, canvas: *eng.Canvas) void {
        canvas.clear(' ', eng.Color{ .r = 0, .g = 0, .b = 0 });
        for (self.game_state.players) |p| {
            canvas.put(p.x, p.y, '@');
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var client = try Client.connect(allocator, "127.0.0.1", 42069);
    defer client.deinit();

    while (true) {
        client.receive();
        std.time.sleep(50 * std.time.ns_per_ms);
    }
}

