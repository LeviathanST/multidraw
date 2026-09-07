const std = @import("std");
const Stroke = @import("Session.zig").Stroke;

const ParseFromValueError = std.json.ParseFromValueError;

pub const InitPayload = struct {
    session_id: []const u8,
};

pub const HistoryPayload = struct {
    strokes: []const Stroke,
};

pub const Message = union(enum) {
    const Self = @This();

    init: InitPayload,
    history: HistoryPayload,
    draw: Stroke,

    pub fn jsonStringify(self: Self, jw: *std.json.Stringify) !void {
        try jw.beginObject();
        try jw.objectField("type");
        try jw.write(@tagName(std.meta.activeTag(self)));

        try jw.objectField("data");
        switch (self) {
            inline else => |p| try jw.write(p),
        }
        try jw.endObject();
    }

    /// TODO: Unhandled edge-caes:
    /// - Wrong orders:
    ///   + The data field appear before the type field
    pub fn jsonParse(
        alloc: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !Message {
        if (.object_begin != try source.next()) return ParseFromValueError.UnexpectedToken;

        var type_str: ?[]const u8 = null;
        var msg: ?Message = null;

        while (true) {
            const field_name_token: std.json.Token = try source.nextAllocMax(alloc, .alloc_if_needed, options.max_value_len.?);
            switch (field_name_token) {
                .object_end => break,
                inline .string, .allocated_string => |value| { // should be always field nname
                    if (std.mem.eql(u8, value, "type")) {
                        const value_token: std.json.Token = try source.nextAllocMax(alloc, .alloc_if_needed, options.max_value_len.?);
                        type_str = switch (value_token) {
                            inline .string, .allocated_string => |slice| try alloc.dupe(u8, slice),
                            else => {
                                return ParseFromValueError.UnknownField;
                            },
                        };
                        continue;
                    }

                    if (type_str == null) {
                        try source.skipValue();
                        continue;
                    }
                    if (!std.mem.eql(u8, value, "data")) {
                        try source.skipValue();
                        continue;
                    }

                    inline for (std.meta.fields(Message)) |f| {
                        if (std.mem.eql(u8, type_str.?, f.name)) {
                            if (f.type == void) {
                                // void isn't really a json type, but we can support void payload union tags with {} as a value.
                                if (.object_begin != try source.next()) return ParseFromValueError.UnexpectedToken;
                                if (.object_end != try source.next()) return ParseFromValueError.UnexpectedToken;
                                msg = @unionInit(Message, f.name, {});
                            } else {
                                // Recurse.
                                msg = @unionInit(Message, f.name, try std.json.innerParse(f.type, alloc, source, options));
                            }
                            break;
                        }
                    } else {
                        return ParseFromValueError.UnknownField;
                    }

                    if (type_str) |s| {
                        alloc.free(s);
                    }
                    continue;
                },
                else => continue,
            }
        }

        if (msg == null) return ParseFromValueError.MissingField;

        return msg.?;
    }
};

test "basic message envelope round-trip" {
    const alloc = std.testing.allocator;

    // init
    const init_original: Message = .{ .init = .{ .session_id = "abc-123" } };
    const init_json = try std.json.Stringify.valueAlloc(alloc, init_original, .{});
    defer alloc.free(init_json);

    const init_parsed = try std.json.parseFromSlice(Message, alloc, init_json, .{});
    defer init_parsed.deinit();

    try std.testing.expectEqualDeep(init_original, init_parsed.value);

    // history
    const history_original: Message = .{ .history = .{ .strokes = &.{
        .{ .drawFrom = .{ .x = 0, .y = 0 }, .drawTo = .{ .x = 1, .y = 1 } },
    } } };
    const history_json = try std.json.Stringify.valueAlloc(alloc, history_original, .{});
    defer alloc.free(history_json);

    const history_parsed = try std.json.parseFromSlice(Message, alloc, history_json, .{});
    defer history_parsed.deinit();

    try std.testing.expectEqualDeep(history_original, history_parsed.value);

    // draw
    const draw_original: Message = .{ .draw = .{
        .drawFrom = .{ .x = 1, .y = 2 },
        .drawTo = .{ .x = 3, .y = 4 },
    } };
    const draw_json = try std.json.Stringify.valueAlloc(alloc, draw_original, .{});
    defer alloc.free(draw_json);

    const draw_parsed = try std.json.parseFromSlice(Message, alloc, draw_json, .{});
    defer draw_parsed.deinit();

    try std.testing.expectEqualDeep(draw_original, draw_parsed.value);
}

test "message tolerates unknown trailing field" {
    const alloc = std.testing.allocator;

    const parsed = try std.json.parseFromSlice(
        Message,
        alloc,
        \\{"type":"draw","data":{"drawFrom":{"x":1,"y":2},"drawTo":{"x":3,"y":4}},"zzz":1}
    ,
        .{},
    );
    defer parsed.deinit();

    try std.testing.expect(parsed.value == .draw);
    try std.testing.expectEqual(@as(f32, 1), parsed.value.draw.drawFrom.x);
}

test "message rejects unknown type" {
    const alloc = std.testing.allocator;

    try std.testing.expectError(
        error.UnknownField,
        std.json.parseFromSlice(Message, alloc, "{\"type\":\"nope\",\"data\":{}}", .{}),
    );
}
