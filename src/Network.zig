const std = @import("std");

/// Shared state for a single player. Sent from server to all clients.
pub const PlayerState = struct {
    id: u32,
    x: i32,
    y: i32,
    ch: u8,
};

pub const GameStatePacket = struct {
    players: []const PlayerState,
};

pub const PlayerInputPacket = struct {
    key: u8,
};

