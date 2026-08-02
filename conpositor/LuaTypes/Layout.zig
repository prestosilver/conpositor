const std = @import("std");
const zlua = @import("zlua");

const Config = @import("../Config.zig");
const Client = @import("../Client.zig");
const Layout = @import("../Layout.zig");
const LuaContext = @import("../LuaContext.zig");

const LuaContainer = @import("Container.zig");

const Lua = zlua.Lua;
const allocator = Config.allocator;

const Self = @This();

child: *Layout,

pub fn getRoot(self: *Self) LuaContainer {
    return .{
        .child = self.child.container,
    };
}

pub fn format(self: Self, writer: *std.Io.Writer) !void {
    try writer.print("{*}", .{self.child});
}

pub fn fromLua(lua: *Lua, _: ?std.mem.Allocator, index: i32) !Self {
    _ = lua.getField(index, "instance");
    const result = try lua.toUserdata(Self, -1);
    lua.pop(1);

    return result.*;
}

pub fn toLua(self: Self, lua: *Lua) void {
    LuaContext.pushT(lua, self, "Layout");
}

pub fn hash(self: *const Self) usize {
    return @intFromPtr(self.child);
}
