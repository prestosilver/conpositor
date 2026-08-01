const std = @import("std");
const zlua = @import("zlua");

const Config = @import("../Config.zig");
const Client = @import("../Client.zig");
const Layout = @import("../Layout.zig");

const Lua = zlua.Lua;
const allocator = Config.allocator;

const Self = @This();

child: *Layout.Container,

pub const LuaMethods = struct {
    pub fn set_stack(parent: *Self, stack: ?u8) void {
        const self = parent.child;

        self.stack = stack;
    }

    pub fn add_child(parent: *Self, x_min: f64, y_min: f64, x_max: f64, y_max: f64) !Self {
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
};

pub fn fromLua(lua: *Lua, _: ?std.mem.Allocator, index: i32) !Self {
    const result = try lua.toUserdata(Self, index);
    return result.*;
}

pub fn toLua(self: Self, lua: *Lua) void {
    const tmp = lua.newUserdata(Self, 0);
    tmp.* = self;

    lua.setMetatableRegistry("Container");
}
