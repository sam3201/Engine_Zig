pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var canvas = Canvas.init(80, 24);
    defer canvas.deinit();

    const input_state = input.InputState.init();

    var stream = try connectToServer();
    defer disconnectFromServer(&stream);

    while (true) {
        canvas.clear();

        try input_state.poll();

        if (input_state.isKeyPressed('q')) break;

        if (input_state.isKeyPressed('w')) try sendInput(&stream, "w");
        if (input_state.isKeyPressed('s')) try sendInput(&stream, "s");
        if (input_state.isKeyPressed('a')) try sendInput(&stream, "a");
        if (input_state.isKeyPressed('d')) try sendInput(&stream, "d");

        try renderGameState(&stream, allocator, &canvas);

        canvas.present();
        std.time.sleep(16_666_666); // ~60 fps
    }
}

