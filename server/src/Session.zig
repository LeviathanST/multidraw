const std = @import("std");
const ws = @import("ws");
const uuid = @import("uuid");

const Self = @This();

id: [36]u8,
strokes: std.ArrayList(Stroke) = .empty,
participants: std.ArrayList(Participant) = .empty,
mutex: std.Io.Mutex = .init,

pub const Participant = struct {
    conn: *ws.Conn,
    isOwner: bool,
};

pub const Stroke = struct {
    drawFrom: Position,
    drawTo: Position,
    pub const Position = struct { x: f32, y: f32 };
};

/// return null if not found any valid params.
pub fn parseIdFromUrl(url: []const u8) ?[]u8 {
    var urlSplitter = std.mem.splitScalar(u8, url, '?');
    _ = urlSplitter.first();

    if (urlSplitter.next()) |params| {
        var paramsSplitter = std.mem.splitScalar(u8, params, '&');

        while (paramsSplitter.next()) |param| {
            if (std.mem.startsWith(u8, param, "sessionId")) {
                var paramSplitter = std.mem.splitScalar(u8, param, '=');
                _ = paramSplitter.first();
                if (paramSplitter.next()) |id| {
                    return @constCast(id);
                }

                break;
            }
        }
    }

    return null;
}

pub fn create(gpa: std.mem.Allocator, owner_conn: *ws.Conn) !Self {
    var pcps = std.ArrayList(Participant).empty;
    try pcps.append(gpa, .{ .conn = owner_conn, .isOwner = true });

    return Self{
        .id = uuid.urn.serialize(uuid.v4.new(owner_conn.io)),
        .participants = pcps,
    };
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    self.strokes.deinit(gpa);
    self.participants.deinit(gpa);
}

pub fn addOneParticipant(self: *Self, gpa: std.mem.Allocator, conn: *ws.Conn) !void {
    try self.participants.append(gpa, .{ .conn = conn, .isOwner = false });
}
