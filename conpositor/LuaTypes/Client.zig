const std = @import("std");
const zlua = @import("zlua");

const Config = @import("../Config.zig");
const Client = @import("../Client.zig");

const LuaClosure = @import("Closure.zig");
const LuaStack = @import("Stack.zig");
const LuaTextModule = @import("TextModule.zig");
const LuaMonitor = @import("Monitor.zig");
const LuaRectangle = @import("Rectangle.zig");
const LuaContainer = @import("Container.zig");
const LuaTag = @import("Tag.zig");
const LuaLayout = @import("Layout.zig");

const Lua = zlua.Lua;
const allocator = Config.allocator;

const Self = @This();

child: *Client,

pub const LuaMethods = struct {
    pub fn get_position(self: *Self) !LuaRectangle {
        return .{
            .x = @floatFromInt(self.child.floating_bounds.x),
            .y = @floatFromInt(self.child.floating_bounds.y),
            .width = @floatFromInt(self.child.floating_bounds.width),
            .height = @floatFromInt(self.child.floating_bounds.height),
        };
    }

    pub fn set_position(self: *Self, target: LuaRectangle) void {
        self.child.setFloatingSize(.{
            .x = @intFromFloat(target.x),
            .y = @intFromFloat(target.y),
            .width = @intFromFloat(target.width),
            .height = @intFromFloat(target.height),
        });
    }

    pub fn get_fullscreen(self: *Self) bool {
        return self.child.fullscreen;
    }

    pub fn set_fullscreen(self: *Self, fullscreen: bool) void {
        self.child.setFullscreen(fullscreen);
    }

    pub fn set_border(self: *Self, border: i32) void {
        self.child.setBorder(border);
    }

    // TODO: Move client icons to lua.
    // tag clients by index, and have lua store/script the icon.
    pub fn set_icon(self: *Self, icon: ?[:0]const u8) void {
        self.child.setIcon(@ptrCast(icon));
    }

    // TODO: Move client labels to lua.
    // tag clients by index, and have lua store/script the label.
    pub fn set_label(self: *Self, label: ?[:0]const u8) void {
        self.child.setLabel(label);
    }

    pub fn get_label(self: *Self) ?[:0]const u8 {
        return self.child.label;
    }

    pub fn get_appid(self: *Self) ?[:0]const u8 {
        return self.child.getAppId();
    }

    pub fn get_title(self: *Self) ?[:0]const u8 {
        return self.child.getTitle();
    }

    pub fn get_icon(self: *Self) ?[:0]const u8 {
        return self.child.icon;
    }

    pub fn set_tag(self: *Self, tag: *LuaTag) void {
        self.child.setTag(tag.id);
    }

    pub fn set_monitor(self: *Self, monitor: LuaMonitor) void {
        self.child.setMonitor(monitor.child);
    }

    pub fn set_stack(self: *Self, stack: u8) void {
        self.child.setContainer(stack);
        self.child.setFloating(false);

        std.log.debug("Set client {f} stack to {}", .{ self, stack });
    }

    pub fn set_container(self: *Self, container: *LuaContainer) void {
        if (container.child.stack) |stack| {
            self.child.setContainer(stack);
            self.child.setFloating(false);

            std.log.debug("Set client {f} stack to {}", .{ self, stack });
        }
    }

    pub fn get_floating(self: *Self) bool {
        return self.child.floating;
    }

    pub fn set_floating(self: *Self, value: bool) void {
        self.child.setFloating(value);
    }

    pub fn get_stack(self: *Self) ?LuaStack {
        if (self.child.floating) return null;
        return .{ .id = self.child.container };
    }

    pub fn close(self: *Self) void {
        self.child.close();
    }

    pub fn raw_set_modules(lua: *Lua) !i32 {
        const old_top = lua.getTop();

        const self: *Self = try lua.toAny(*Self, -2);

        for (self.child.tab.left_modules.items) |*module| module.deinit();
        for (self.child.tab.center_modules.items) |*module| module.deinit();
        for (self.child.tab.right_modules.items) |*module| module.deinit();

        self.child.tab.left_modules.clearRetainingCapacity();
        self.child.tab.center_modules.clearRetainingCapacity();
        self.child.tab.right_modules.clearRetainingCapacity();
        self.child.dirty.title = true;

        _ = lua.getField(-1, "left");
        const left_len = lua.lenRaw(-1);

        for (1..left_len + 1) |idx| {
            _ = try lua.pushAny(idx);
            _ = lua.getTable(-2);
            defer lua.pop(1);

            try self.child.tab.left_modules.append(try lua.toAny(LuaTextModule, -1));
        }

        lua.pop(1);

        _ = lua.getField(-1, "center");
        const center_len = lua.lenRaw(-1);

        for (1..center_len + 1) |idx| {
            _ = try lua.pushAny(idx);
            _ = lua.getTable(-2);
            defer lua.pop(1);

            try self.child.tab.center_modules.append(try lua.toAny(LuaTextModule, -1));
        }

        lua.pop(1);

        _ = lua.getField(-1, "right");
        const right_len = lua.lenRaw(-1);

        for (1..right_len + 1) |idx| {
            _ = try lua.pushAny(idx);
            _ = lua.getTable(-2);
            defer lua.pop(1);

            try self.child.tab.right_modules.append(try lua.toAny(LuaTextModule, -1));
        }

        lua.pop(1);

        if (old_top != lua.getTop() + 0)
            return error.LuaError;

        return 0;
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

    lua.setMetatableRegistry("Client");
}
