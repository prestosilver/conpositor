const std = @import("std");
const zlua = @import("zlua");

const Config = @import("../Config.zig");
const Monitor = @import("../Monitor.zig");
const LuaContext = @import("../LuaContext.zig");

const LuaClosure = @import("Closure.zig");
const LuaClient = @import("Client.zig");
const LuaRectangle = @import("Rectangle.zig");
const LuaTag = @import("Tag.zig");
const LuaLayout = @import("Layout.zig");

const Lua = zlua.Lua;
const allocator = Config.allocator;

const Self = @This();

child: *Monitor,

pub fn getPosition(self: *Self) !LuaRectangle {
    return .{
        .x = @floatFromInt(self.child.mode.x),
        .y = @floatFromInt(self.child.mode.y),
        .width = @floatFromInt(self.child.mode.width),
        .height = @floatFromInt(self.child.mode.height),
    };
}

pub fn getActiveTag(self: *Self) !LuaTag {
    return .{ .id = self.child.tag };
}

pub fn setActiveTag(self: *Self, tag: *LuaTag) void {
    self.child.setActiveTag(tag.id);

    std.log.debug("Set monitor {f} tag to {f}", .{ self, tag });
}

pub fn getLayout(self: *Self) ?LuaLayout {
    return .{
        .child = self.child.layout orelse return null,
    };
}

pub fn setLayout(self: *Self, layout: LuaLayout) void {
    self.child.setLayout(layout.child);

    std.log.debug("Set monitor {f} layout to {f}", .{ self, layout });
}

pub fn setInnerGaps(self: *Self, size: i32) void {
    self.child.setGaps(.inner, size);
}

pub fn setOuterGaps(self: *Self, size: i32) void {
    self.child.setGaps(.outer, size);
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
    LuaContext.pushT(lua, self, "Monitor");
}

pub fn hash(self: *const Self) usize {
    return @intFromPtr(self.child);
}
