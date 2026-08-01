const std = @import("std");
const zlua = @import("zlua");

const Config = @import("../Config.zig");
const Monitor = @import("../Monitor.zig");

const LuaClosure = @import("Closure.zig");
const LuaClient = @import("Client.zig");
const LuaRectangle = @import("Rectangle.zig");
const LuaTag = @import("Tag.zig");
const LuaLayout = @import("Layout.zig");

const Lua = zlua.Lua;
const allocator = Config.allocator;

const Self = @This();

child: *Monitor,

pub const LuaMethods = struct {
    pub fn get_size(self: *Self) !LuaRectangle {
        return .{
            .x = @floatFromInt(self.child.mode.x),
            .y = @floatFromInt(self.child.mode.y),
            .width = @floatFromInt(self.child.mode.width),
            .height = @floatFromInt(self.child.mode.height),
        };
    }

    pub fn get_tag(self: *Self) !LuaTag {
        return .{ .id = self.child.tag };
    }

    pub fn set_tag(self: *Self, tag: *LuaTag) void {
        self.child.setActiveTag(tag.id);

        std.log.debug("Set monitor {f} tag to {f}", .{ self, tag });
    }

    pub fn get_layout(self: *Self) ?LuaLayout {
        return .{
            .child = self.child.layout orelse return null,
        };
    }

    pub fn set_layout(self: *Self, layout: LuaLayout) void {
        self.child.setLayout(layout.child);

        std.log.debug("Set monitor {f} layout to {f}", .{ self, layout });
    }

    pub fn set_inner_gaps(self: *Self, size: i32) void {
        self.child.setGaps(.inner, size);
    }

    pub fn set_outer_gaps(self: *Self, size: i32) void {
        self.child.setGaps(.outer, size);
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

    lua.setMetatableRegistry("Monitor");
}
