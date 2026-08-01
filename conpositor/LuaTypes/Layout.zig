const std = @import("std");
const zlua = @import("zlua");

const Config = @import("../Config.zig");
const Client = @import("../Client.zig");
const Layout = @import("../Layout.zig");

const LuaContainer = @import("Container.zig");

const Lua = zlua.Lua;
const allocator = Config.allocator;

const Self = @This();

child: *Layout,

pub const LuaMethods = struct {
    pub fn root(self: *Self) LuaContainer {
        return .{
            .child = self.child.container,
        };
    }
};

pub fn format(self: Self, writer: *std.Io.Writer) !void {
    try writer.print("{*}", .{self.child});
}

pub fn fromLua(lua: *Lua, _: ?std.mem.Allocator, index: i32) !Self {
    const result = try lua.toUserdata(Self, index);
    return result.*;
}

pub fn toLua(self: Self, lua: *Lua) void {
    const tmp = lua.newUserdata(Self, 0);
    tmp.* = self;

    lua.setMetatableRegistry("Layout");
}
