const std = @import("std");
const ws = @import("ws");
const uuid = @import("uuid");

const Self = @This();

id: [36]u8,
strokes: std.ArrayList(Stroke) = .empty,
mutex: std.Io.Mutex = .init,
pcp_list: ParticipantList = .{},

pub const WS_MESSAGE = enum {
    INIT,
    HISTORY,
};

pub const ParticipantList = struct {
    participants: std.ArrayList(Participant) = .empty,
    mut: std.Io.Mutex = .init,

    pub const Participant = struct {
        conn: *ws.Conn,
        isOwner: bool,
    };

    pub fn fromOwner(gpa: std.mem.Allocator, owner_conn: *ws.Conn) !ParticipantList {
        var list = ParticipantList{};
        try list.participants.append(gpa, .{ .conn = owner_conn, .isOwner = true });
        return list;
    }

    pub fn addOne(self: *ParticipantList, gpa: std.mem.Allocator, conn: *ws.Conn) !void {
        try self.participants.append(gpa, .{ .conn = conn, .isOwner = false });
    }
};

pub const Stroke = struct {
    drawFrom: Position,
    drawTo: Position,
    pub const Position = struct { x: f32, y: f32 };
};

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    self.strokes.deinit(gpa);
    self.pcp_list.participants.deinit(gpa);
}

pub fn create(gpa: std.mem.Allocator, owner_conn: *ws.Conn) !Self {
    return Self{
        .id = uuid.urn.serialize(uuid.v4.new(owner_conn.io)),
        .pcp_list = try .fromOwner(gpa, owner_conn),
    };
}

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
