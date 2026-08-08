const std = @import("std");
const zlua = @import("zlua");

const Config = @import("../Config.zig");
const LuaContext = @import("../LuaContext.zig");

const Lua = zlua.Lua;

const Self = @This();

id: u8,

pub fn format(self: Self, writer: *std.Io.Writer) !void {
    try writer.print("Tag#{}", .{self.id});
}

pub fn fromLua(lua: *Lua, _: ?std.mem.Allocator, index: i32) !Self {
    _ = lua.getField(index, "instance");
    const result = try lua.toUserdata(Self, -1);
    lua.pop(1);

    return result.*;
}

pub fn toLua(self: Self, lua: *Lua) void {
    LuaContext.pushT(lua, self, "Tag");
}

pub fn hash(self: *const Self) usize {
    return @intCast(self.id);
}
