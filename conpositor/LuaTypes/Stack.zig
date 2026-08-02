const std = @import("std");
const zlua = @import("zlua");

const Config = @import("../Config.zig");
const Client = @import("../Client.zig");

const LuaClosure = @import("Closure.zig");
const LuaTextModule = @import("TextModule.zig");
const LuaMonitor = @import("Monitor.zig");
const LuaRectangle = @import("Rectangle.zig");
const LuaContainer = @import("Container.zig");
const LuaTag = @import("Tag.zig");
const LuaLayout = @import("Layout.zig");

const Lua = zlua.Lua;
const allocator = Config.allocator;

const Self = @This();

id: u8,

pub fn format(self: *Self, writer: *std.Io.Writer) !void {
    try writer.print("stack#{}", .{self.id});
}

pub fn fromLua(lua: *Lua, _: ?std.mem.Allocator, index: i32) !Self {
    const result = try lua.toUserdata(Self, index);
    return result.*;
}

pub fn toLua(self: Self, lua: *Lua) void {
    const tmp = lua.newUserdata(Self, 0);
    tmp.* = self;

    lua.setMetatableRegistry("Stack");
}
