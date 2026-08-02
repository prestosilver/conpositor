const std = @import("std");
const zlua = @import("zlua");

const Config = @import("../Config.zig");

const Lua = zlua.Lua;

const Self = @This();

id: u8,

pub fn format(self: Self, writer: *std.Io.Writer) !void {
    try writer.print("Tag#{}", .{self.id});
}

pub fn fromLua(lua: *Lua, _: ?std.mem.Allocator, index: i32) !Self {
    const result = try lua.toUserdata(Self, index);
    return result.*;
}

pub fn toLua(self: Self, lua: *Lua) void {
    const tmp = lua.newUserdata(Self, 0);
    tmp.* = self;

    lua.setMetatableRegistry("Tag");
}
