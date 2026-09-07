const std = @import("std");
const ws = @import("ws");
const dotenv = @import("dotenv");
const uuid = @import("uuid");

const Session = @import("Session.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var osEnv = init.environ_map;
    var env = dotenv.Dotenv.init(allocator, .{});
    defer env.deinit();

    var server = try ws.Server(Handler).init(init.io, allocator, .{
        .port = parsePort: {
            const envPort = env.get("WS_PORT") orelse osEnv.get("WS_PORT");
            if (envPort != null)
                break :parsePort try std.fmt.parseInt(u16, envPort.?, 10);

            break :parsePort 3030;
        },
        .address = env.get("WS_ADDR") orelse osEnv.get("WS_ADDR") orelse "127.0.0.1",
        .handshake = .{
            .timeout = 3,
            .max_size = 1024,
            .max_headers = 0,
        },
    });

    var app = App.init(allocator);
    defer app.deinit();

    // this blocks
    try server.listen(&app);
}

const Handler = struct {
    app: *App,
    conn: *ws.Conn,
    session_id: []u8,

    pub fn init(h: *ws.Handshake, conn: *ws.Conn, app: *App) !Handler {
        const id = Session.parseIdFromUrl(h.url) orelse {
            return .{
                .session_id = try app.addSession(conn),
                .app = app,
                .conn = conn,
            };
        };

        try app.mutex.lock(conn.io);
        const s = app.sessions.getPtr(id) orelse {
            app.mutex.unlock(conn.io);
            return .{
                .session_id = try app.addSession(conn),
                .app = app,
                .conn = conn,
            };
        };

        {
            defer app.mutex.unlock(conn.io);

            try s.mutex.lock(conn.io);
            defer s.mutex.unlock(conn.io);
            try s.addOneParticipant(app.gpa, conn);
        }

        return .{
            .session_id = try app.gpa.dupe(u8, id),
            .app = app,
            .conn = conn,
        };
    }

    pub fn afterInit(self: *Handler) !void {
        var stroke_msg = self.conn.writeBuffer(self.app.gpa, .text);
        defer stroke_msg.deinit();

        var isOwner = false;

        { // format json string
            try self.app.mutex.lock(self.conn.io);
            defer self.app.mutex.unlock(self.conn.io);

            const s =
                self
                    .app
                    .sessions
                    .getPtr(self.session_id) orelse return;

            try s.*.mutex.lock(self.conn.io);
            defer s.*.mutex.unlock(self.conn.io);

            for (s.participants.items) |pcp| {
                if (pcp.conn == self.conn) {
                    isOwner = pcp.isOwner;
                    break;
                }
            }

            try std.json.fmt(
                s.strokes.items,
                .{},
            ).format(&stroke_msg.interface);
        }

        if (isOwner) {
            var init_msg = self.conn.writeBuffer(self.app.gpa, .text);
            defer init_msg.deinit();

            try std.json.fmt(.{
                .type = "init",
                .session_id = self.session_id,
            }, .{}).format(&init_msg.interface);

            try init_msg.send();
        }

        try stroke_msg.send();
    }

    pub fn close(self: *Handler) void {
        if (self.wrappedClose()) |_| {
            //
        } else |_| {
            std.log.err("Cannot close the connection because the lock is canceled!", .{});
        }
    }

    fn wrappedClose(self: *Handler) !void {
        try self.app.mutex.lock(self.conn.io);
        defer self.app.mutex.unlock(self.conn.io);

        if (self.app.sessions.getPtr(self.session_id)) |s| {
            const pcps = &s.participants;

            try s.mutex.lock(self.conn.io);
            for (pcps.items, 0..) |pcp, i| {
                if (pcp.conn == self.conn) {
                    _ = pcps.*.swapRemove(i);
                    break;
                }
            }
            const remains = pcps.items.len;
            s.mutex.unlock(self.conn.io);

            if (remains == 0) {
                const remove = self.app.sessions.fetchRemove(self.session_id);
                if (remove) |*r| {
                    self.app.gpa.free(r.key);
                    @constCast(r).value.deinit(self.app.gpa);
                }
            }
            self.app.gpa.free(self.session_id);
            std.log.info("close conn={*}", .{self.conn});
        }
    }

    pub fn clientMessage(self: *Handler, data: []const u8) !void {
        try self.app.mutex.lock(self.conn.io);
        defer self.app.mutex.unlock(self.conn.io);
        const s = self.app.sessions.getPtr(self.session_id) orelse return;

        // avoid touching to the list when iterate
        var pcps = clone: {
            try s.mutex.lock(self.conn.io);
            defer s.mutex.unlock(self.conn.io);
            break :clone try s.participants.clone(self.app.gpa);
        };
        defer pcps.deinit(self.app.gpa);

        const parsed = try std.json.parseFromSlice([]Session.Stroke, self.app.gpa, data, .{});
        defer parsed.deinit();
        if (parsed.value.len == 0) return;

        {
            try s.mutex.lock(self.conn.io);
            defer s.mutex.unlock(self.conn.io);
            try s.strokes.append(self.app.gpa, parsed.value[0]);
        }

        for (pcps.items) |pcp| {
            if (pcp.conn == self.conn) continue;

            if (pcp.conn.write(data)) |_| {
                // success, nothing to do
            } else |err| {
                std.log.err("Errors occur when sending message: {s}", .{@errorName(err)});
            }
        }
    }
};

const App = struct {
    gpa: std.mem.Allocator,
    sessions: std.StringHashMap(Session),
    mutex: std.Io.Mutex = .init,

    pub fn init(gpa: std.mem.Allocator) App {
        return .{
            .gpa = gpa,
            .sessions = .init(gpa),
        };
    }

    pub fn deinit(self: *App) void {
        self.sessions.deinit();
    }

    /// The caller will own the return memory. Call `free` after finish.
    /// Create a new session with one connection is the owner and return the session id
    pub fn addSession(self: *App, owner_conn: *ws.Conn) ![]u8 {
        try self.mutex.lock(owner_conn.io);
        defer self.mutex.unlock(owner_conn.io);

        const s = try Session.create(self.gpa, owner_conn);
        // seperate owners to avoid freeing the memory after a connection
        // is closed but the session is still valid
        try self.sessions.put(try self.gpa.dupe(u8, &s.id), s);
        return try self.gpa.dupe(u8, &s.id);
    }
};
