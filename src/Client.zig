const std = @import("std");
const net = std.net;
const json = std.json;
const eng = @import("Engine.zig");

const GameState = struct {
    tick: u64,
    players: []PlayerState,
};

const PlayerState = struct {
    id: u32,
    x: i32,
    y: i32,
    hp: i32,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    stream: net.Stream,
    game_state: GameState,
    connected: bool,

    pub fn connect(allocator: std.mem.Allocator, host: []const u8, port: u16) !Client {
        const address = try net.Address.parseIp4(host, port);
        const stream = try net.tcpConnectToAddress(address);
        std.debug.print("Connected to server at {s}:{d}\n", .{ host, port });

        return .{
            .allocator = allocator,
            .stream = stream,
            .game_state = .{ .tick = 0, .players = &[_]PlayerState{} },
            .connected = true,
        };
    }

    pub fn deinit(self: *Client) void {
        self.stream.close();
    }

    pub fn sendInput(self: *Client, msg: []const u8) void {
        _ = self.stream.writer().writeAll(msg) catch {};
    }

    pub fn update(self: *Client, canvas: *eng.Canvas) void {
        var buf: [2048]u8 = undefined;
        const len = self.stream.reader().read(&buf) catch return;
        if (len == 0) return;

        var parsed = json.parseFromSlice(GameState, self.allocator, buf[0..len], .{}) catch return;
        defer parsed.deinit();

        self.game_state = parsed.value;

        // Mirror world
        canvas.clear(' ', eng.Color{ .r = 0, .g = 0, .b = 0 });
        for (self.game_state.players) |p| {
            canvas.put(p.x, p.y, '@');
        }
    }
};

