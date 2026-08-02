const std = @import("std");
const zlua = @import("zlua");

const Config = @import("../Config.zig");
const Client = @import("../Client.zig");
const LuaContext = @import("../LuaContext.zig");

const LuaClosure = @import("Closure.zig");
const LuaClient = @import("Client.zig");

const Lua = zlua.Lua;
const allocator = Config.allocator;

const Self = @This();

calls: LuaClosure,
lua: *Lua,

pub fn new(text: LuaClosure) Self {
    std.log.debug("New lua text module {f}", .{text});

    return .{
        .calls = text,
        .lua = text.lua,
    };
}

pub fn getText(self: *Self, client: *Client) ![:0]const u8 {
    const lua = self.lua;

    const old_top = lua.getTop();

    try lua.pushAny(self.calls);
    try lua.pushAny(LuaClient{ .child = client });
    lua.protectedCall(.{ .args = 1, .results = 1 }) catch |err| {
        std.log.err("{s} Error: {s}", .{ @errorName(err), self.lua.toString(-1) catch "unknown" });
        self.lua.pop(1);

        return try allocator.dupeZ(u8, "Err");
    };

    const lua_result: []const u8 = lua.toString(-1) catch "";
    const result = try allocator.dupeZ(u8, lua_result);
    lua.pop(1);

    if (old_top != lua.getTop())
        return error.LuaError;

    return result;
}

pub fn luaGC(self: *Self) void {
    self.calls.deinit();
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn format(self: Self, writer: *std.Io.Writer) !void {
    try writer.print("TextModule({f})", .{self.calls});
}

pub fn fromLua(lua: *Lua, _: ?std.mem.Allocator, index: i32) !Self {
    _ = lua.getField(index, "instance");
    const result = try lua.toUserdata(Self, -1);
    lua.pop(1);

    return result.*;
}

pub fn toLua(self: Self, lua: *Lua) void {
    LuaContext.pushT(lua, self, "TextModule");
}

pub fn hash(self: *const Self) usize {
    return @intFromPtr(self);
}
