// keyboard.zig - Simple keyboard input test for debugging
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

    var events = try std.ArrayList([]const u8).initCapacity(allocator, 15);
    defer {
        for (events.items) |event| {
            allocator.free(event);
        }
        events.deinit(allocator);
    }

    var frame_count: usize = 0;

    std.debug.print("Keyboard Test Started - Enter Keys, press Ctrl-C to quit\n", .{});

    engine.running = true;
    while (engine.running) {
        engine.clock.tick();
        frame_count += 1;

        if (try Engine.readKey()) |key| {
            if (key == 'q' or key == 'Q') {
                break;
            }
            
                try events.append(allocator, try std.fmt.allocPrint(allocator, "Frame {}: Key '{c}'", .{ frame_count, key }));
                if (events.items.len > 15) {
                    allocator.free(events.orderedRemove(0));
                }
            }

        }

        engine.canvas.clear(' ', engine.background_color);

        const title = "=== KEYBOARD INPUT TEST ===";
        const title_x = @divTrunc(@as(i32, @intCast(engine.canvas.width)) - @as(i32, @intCast(title.len)), 2);
        for (title, 0..) |ch, i| {
            engine.canvas.put(title_x + @as(i32, @intCast(i)), 1, ch);
            engine.canvas.fillColor(title_x + @as(i32, @intCast(i)), 1, .{ .r = 255, .g = 255, .b = 100 });
        }

        const instructions = "Enter keys, press Ctrl-C to quit";
        const inst_x = @divTrunc(@as(i32, @intCast(engine.canvas.width)) - @as(i32, @intCast(instructions.len)), 2);
        for (instructions, 0..) |ch, i| {
            engine.canvas.put(inst_x + @as(i32, @intCast(i)), 3, ch);
            engine.canvas.fillColor(inst_x + @as(i32, @intCast(i)), 3, .{ .r = 200, .g = 200, .b = 200 });
        }


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
