const std = @import("std");
const Engine = @import("Engine.zig");
const WorldManager = @import("WorldManager.zig");
const Player = @import("Player.zig");
const WASD_BINDINGS = @import("Player.zig").WASD_BINDINGS;
const ARROW_BINDINGS = @import("Player.zig").ARROW_BINDINGS;

var global_world_manager: ?*WorldManager.WorldManager = null;
var current_input: ?u8 = null;

pub fn main() !void {
    const WIDTH: usize = 80;
    const HEIGHT: usize = 24;
    const FPS: f64 = 10;
    const black = Engine.Color{ .r = 0, .g = 0, .b = 0 };

    var eng = try Engine.Engine.init(std.heap.page_allocator, WIDTH, HEIGHT, FPS, black);
    defer eng.deinit();

    const player = try Player.createWASDPlayer(std.heap.page_allocator, 0, 0);

    var world_manager = try WorldManager.WorldManager.init(std.heap.page_allocator, &eng.canvas, player);
    defer world_manager.deinit();

    global_world_manager = &world_manager;

    const UpdateFunctions = struct {
        fn update() void {
            if (global_world_manager) |wm| {
                if (current_input) |input| {
                    wm.processPlayerInput(input) catch {};
                    current_input = null;
                }
                wm.draw();
            }
        }
    };

    eng.setUpdateFn(&UpdateFunctions.update);

    try eng.run();
}

pub fn setInput(input: u8) void {
    current_input = input;
}
