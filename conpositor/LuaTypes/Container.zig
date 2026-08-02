const std = @import("std");
const zlua = @import("zlua");

const Config = @import("../Config.zig");
const Client = @import("../Client.zig");
const Layout = @import("../Layout.zig");
const LuaContext = @import("../LuaContext.zig");

const Lua = zlua.Lua;
const allocator = Config.allocator;

const Self = @This();

child: *Layout.Container,

pub fn setStack(parent: *Self, stack: ?u8) void {
    const self = parent.child;

    self.stack = stack;
}

pub fn addChild(parent: *Self, x_min: f64, y_min: f64, x_max: f64, y_max: f64) !Self {
    const self = parent.child;

    const container = try allocator.create(Layout.Container);
    container.* = .{
        .stack = null,
        .size = .{
            .x_min = x_min,
            .x_max = x_max,
            .y_min = y_min,
            .y_max = y_max,
        },
        .children = &.{},
    };

    self.children = try allocator.realloc(self.children, self.children.len + 1);
    self.children[self.children.len - 1] = container;

    return .{ .child = container };
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
    LuaContext.pushT(lua, self, "Container");
}

pub fn hash(self: *const Self) usize {
    return @intFromPtr(self.child);
}
