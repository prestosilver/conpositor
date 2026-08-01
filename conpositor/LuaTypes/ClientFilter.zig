const std = @import("std");

const allocator = @import("../Config.zig").allocator;

const zlua = @import("zlua");
const Lua = zlua.Lua;

const Self = @This();

title: ?[]const u8,
appid: ?[]const u8,

pub const LuaMethods = struct {};

pub fn matches(self: *const Self, title: []const u8, appid: []const u8) bool {
    if (self.title) |trg_title|
        if (!std.mem.eql(u8, trg_title, title))
            return false;

    if (self.appid) |trg_appid|
        if (!std.mem.eql(u8, trg_appid, appid))
            return false;

    return true;
}

pub fn fromLua(lua: *Lua, _: ?std.mem.Allocator, index: i32) !Self {
    _ = lua.getField(index, "title");
    const lua_title = lua.toAny(?[]const u8, -1) catch null;
    const title = if (lua_title) |new_title| try allocator.dupe(u8, new_title) else null;
    lua.pop(1);

    _ = lua.getField(index, "appid");
    const lua_appid = lua.toAny(?[]const u8, -1) catch null;
    const appid = if (lua_appid) |new_appid| try allocator.dupe(u8, new_appid) else null;
    lua.pop(1);

    return .{
        .title = title,
        .appid = appid,
    };
}

pub fn deinit(self: *const Self) void {
    if (self.title) |title|
        allocator.free(title);

    if (self.appid) |appid|
        allocator.free(appid);
}
