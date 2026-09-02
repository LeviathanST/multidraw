const std = @import("std");
const ws = @import("ws");
const dotenv = @import("dotenv");

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

    var app = App{ .gpa = allocator };
    defer app.deinit();

    // this blocks
    try server.listen(&app);
}

const Handler = struct {
    app: *App,
    conn: *ws.Conn,

    pub fn init(h: *ws.Handshake, conn: *ws.Conn, app: *App) !Handler {
        // `h` contains the initial websocket "handshake" request
        // It can be used to apply application-specific logic to verify / allow
        // the connection (e.g. valid url, query string parameters, or headers)

        _ = h; // we're not using this in our simple case
        try app.conn_list.mut.lock(conn.io);
        defer app.conn_list.mut.unlock(conn.io);

        try app.conn_list.conns.append(app.gpa, conn);

        return .{
            .app = app,
            .conn = conn,
        };
    }

    pub fn close(self: *Handler) void {
        if (self.app.conn_list.mut.lock(self.conn.io)) |_| {
            defer self.app.conn_list.mut.unlock(self.conn.io);

            for (self.app.conn_list.conns.items, 0..) |conn, i| {
                if (conn == self.conn) {
                    _ = self.app.conn_list.conns.swapRemove(i);
                    break;
                }
            }
        } else |_| {
            std.log.err("Cannot close the connection because the lock is canceled!", .{});
        }
    }

    pub fn clientMessage(self: *Handler, data: []const u8) !void {
        // avoid touching to the list when iterate
        var conns = clone: {
            try self.app.conn_list.mut.lock(self.conn.io);
            defer self.app.conn_list.mut.unlock(self.conn.io);
            break :clone try self.app.conn_list.conns.clone(self.app.gpa);
        };
        defer conns.deinit(self.app.gpa);

        for (conns.items) |conn| {
            if (conn == self.conn) continue;
            if (conn.write(data)) |_| {
                // success, nothing to do
            } else |err| {
                std.log.err("Errors occur when sending message: {s}", .{@errorName(err)});
            }
        }
    }
};

const App = struct {
    gpa: std.mem.Allocator,

    conn_list: ConnList = .{},

    pub const ConnList = struct {
        conns: std.ArrayList(*ws.Conn) = .empty,
        mut: std.Io.Mutex = .init,
    };

    pub fn deinit(self: *App) void {
        self.conn_list.conns.deinit(self.gpa);
    }
};
