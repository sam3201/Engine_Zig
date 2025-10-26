// mouse_test.zig - Simple mouse input test for debugging
const std = @import("std");
const Engine = @import("Engine.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var engine = try Engine.Engine.init(
        allocator,
        80,
        40,
        60,
        Engine.Color{ .r = 0, .g = 0, .b = 20 },
    );
    defer engine.deinit();

    var terminal_guard = try Engine.TerminalGuard.init();
    defer terminal_guard.deinit();

    // Enable mouse tracking
    try Engine.enableMouseTracking();
    defer Engine.disableMouseTracking() catch {};

    var events = std.ArrayList([]const u8).init(allocator);
    defer {
        for (events.items) |event| {
            allocator.free(event);
        }
        events.deinit();
    }

    var mouse_state = Engine.MouseState{};
    var frame_count: usize = 0;

    std.debug.print("Mouse Test Started - Move mouse, click buttons, press Q to quit\n", .{});

    engine.running = true;
    while (engine.running) {
        engine.clock.tick();
        frame_count += 1;

        // Check for keyboard input
        if (try Engine.readKey()) |key| {
            if (key == 'q' or key == 'Q' or key == 27) {
                break;
            }
            
            const key_event = try std.fmt.allocPrint(
                allocator,
                "Frame {}: Key pressed: {} ('{c}')",
                .{ frame_count, key, if (key >= 32 and key <= 126) key else '?' },
            );
            try events.append(key_event);
            if (events.items.len > 15) {
                allocator.free(events.orderedRemove(0));
            }
        }

        // Check for mouse input
        if (try Engine.readMouse()) |new_mouse| {
            mouse_state = new_mouse;
            
            const button_state = if (mouse_state.left_button)
                "LEFT"
            else if (mouse_state.right_button)
                "RIGHT"
            else if (mouse_state.middle_button)
                "MIDDLE"
            else
                "NONE";

            const mouse_event = try std.fmt.allocPrint(
                allocator,
                "Frame {}: Mouse at ({}, {}) delta=({}, {}) button={}",
                .{ 
                    frame_count, 
                    mouse_state.x, 
                    mouse_state.y,
                    mouse_state.delta_x,
                    mouse_state.delta_y,
                    button_state,
                },
            );
            try events.append(mouse_event);
            if (events.items.len > 15) {
                allocator.free(events.orderedRemove(0));
            }
        }

        // Clear screen
        engine.canvas.clear(' ', engine.background_color);

        // Draw title
        const title = "=== MOUSE INPUT TEST ===";
        const title_x = @divTrunc(@as(i32, @intCast(engine.canvas.width)) - @as(i32, @intCast(title.len)), 2);
        for (title, 0..) |ch, i| {
            engine.canvas.put(title_x + @as(i32, @intCast(i)), 1, ch);
            engine.canvas.fillColor(title_x + @as(i32, @intCast(i)), 1, .{ .r = 255, .g = 255, .b = 100 });
        }

        // Draw instructions
        const instructions = "Move mouse, click buttons | Press Q to quit";
        const inst_x = @divTrunc(@as(i32, @intCast(engine.canvas.width)) - @as(i32, @intCast(instructions.len)), 2);
        for (instructions, 0..) |ch, i| {
            engine.canvas.put(inst_x + @as(i32, @intCast(i)), 3, ch);
            engine.canvas.fillColor(inst_x + @as(i32, @intCast(i)), 3, .{ .r = 200, .g = 200, .b = 200 });
        }

        // Draw current mouse state
        const mouse_info = try std.fmt.allocPrint(
            allocator,
            "Mouse: X={} Y={} | Delta: X={} Y={} | Buttons: L={} R={} M={}",
            .{
                mouse_state.x,
                mouse_state.y,
                mouse_state.delta_x,
                mouse_state.delta_y,
                mouse_state.left_button,
                mouse_state.right_button,
                mouse_state.middle_button,
            },
        );
        defer allocator.free(mouse_info);

        const info_y: i32 = 5;
        for (mouse_info, 0..) |ch, i| {
            if (i < engine.canvas.width) {
                engine.canvas.put(@as(i32, @intCast(i)), info_y, ch);
                engine.canvas.fillColor(@as(i32, @intCast(i)), info_y, .{ .r = 100, .g = 255, .b = 100 });
            }
        }

        // Draw event log
        const log_title = "--- Event Log (last 15 events) ---";
        const log_x = 2;
        var log_y: i32 = 7;
        for (log_title, 0..) |ch, i| {
            engine.canvas.put(log_x + @as(i32, @intCast(i)), log_y, ch);
            engine.canvas.fillColor(log_x + @as(i32, @intCast(i)), log_y, .{ .r = 255, .g = 200, .b = 100 });
        }
        log_y += 2;

        // Draw events (newest first)
        var event_idx = events.items.len;
        while (event_idx > 0 and log_y < engine.canvas.height - 2) {
            event_idx -= 1;
            const event = events.items[event_idx];
            
            for (event, 0..) |ch, i| {
                const x = log_x + @as(i32, @intCast(i));
                if (x < engine.canvas.width) {
                    engine.canvas.put(x, log_y, ch);
                    engine.canvas.fillColor(x, log_y, .{ .r = 180, .g = 180, .b = 180 });
                }
            }
            log_y += 1;
        }

        // Draw mouse cursor at current position if within bounds
        if (mouse_state.x >= 0 and mouse_state.x < engine.canvas.width and
            mouse_state.y >= 0 and mouse_state.y < engine.canvas.height)
        {
            const cursor_color = if (mouse_state.left_button)
                Engine.Color{ .r = 255, .g = 0, .b = 0 }
            else if (mouse_state.right_button)
                Engine.Color{ .r = 0, .g = 0, .b = 255 }
            else if (mouse_state.middle_button)
                Engine.Color{ .r = 255, .g = 255, .b = 0 }
            else
                Engine.Color{ .r = 255, .g = 255, .b = 255 };

            engine.canvas.put(mouse_state.x, mouse_state.y, 'X');
            engine.canvas.fillColor(mouse_state.x, mouse_state.y, cursor_color);
        }

        // Render frame
        try engine.canvas.flushToTerminal();
        engine.clock.sleepUntilNextFrame();
    }

    std.debug.print("\nMouse test finished. Total events: {}\n", .{events.items.len});
}
