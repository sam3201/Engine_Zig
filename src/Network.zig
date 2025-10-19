const std = @import("std");

/// Shared state for a single player. Sent from server to all clients.
pub const PlayerState = struct {
    id: u32,
    x: i32,
    y: i32,
    ch: u8,
};

/// Packet sent from Server -> Client containing the state of all players.
pub const GameStatePacket = struct {
    players: []const PlayerState,
};

/// Packet sent from Client -> Server containing a key press.
pub const PlayerInputPacket = struct {
    key: u8,
};

