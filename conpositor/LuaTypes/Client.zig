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

const LuaContext = @import("../LuaContext.zig");

const Lua = zlua.Lua;
const allocator = Config.allocator;

const Self = @This();

child: *Client,

pub fn getPosition(self: *Self) !LuaRectangle {
    return .{
        .x = @floatFromInt(self.child.floating_bounds.x),
        .y = @floatFromInt(self.child.floating_bounds.y),
        .width = @floatFromInt(self.child.floating_bounds.width),
        .height = @floatFromInt(self.child.floating_bounds.height),
    };
}

pub fn setPosition(self: *Self, target: LuaRectangle) void {
    self.child.setFloatingSize(.{
        .x = @intFromFloat(target.x),
        .y = @intFromFloat(target.y),
        .width = @intFromFloat(target.width),
        .height = @intFromFloat(target.height),
    });
}

pub fn getFullscreen(self: *Self) bool {
    return self.child.fullscreen;
}

pub fn setFullscreen(self: *Self, fullscreen: bool) void {
    self.child.setFullscreen(fullscreen);
}

pub fn setBorder(self: *Self, border: i32) void {
    self.child.setBorder(border);
}

// TODO: Move client icons to lua.
// tag clients by index, and have lua store/script the icon.
pub fn setIcon(self: *Self, icon: ?[:0]const u8) void {
    self.child.setIcon(@ptrCast(icon));
}

// TODO: Move client labels to lua.
// tag clients by index, and have lua store/script the label.
pub fn setLabel(self: *Self, label: ?[:0]const u8) void {
    self.child.setLabel(label);
}

pub fn getIcon(self: *Self) ?[:0]const u8 {
    return self.child.icon;
}

pub fn getLabel(self: *Self) ?[:0]const u8 {
    return self.child.label;
}

pub fn getAppid(self: *Self) ?[:0]const u8 {
    return self.child.getAppId();
}

pub fn getTitle(self: *Self) ?[:0]const u8 {
    return self.child.getTitle();
}

pub fn setTag(self: *Self, tag: LuaTag) void {
    self.child.setTag(tag.id);
}

pub fn setMonitor(self: *Self, monitor: LuaMonitor) void {
    self.child.setMonitor(monitor.child);
}

pub fn getStack(self: *Self) ?LuaStack {
    if (self.child.floating) return null;
    return .{ .id = self.child.container };
}

pub fn setStack(self: *Self, stack: u8) void {
    self.child.setContainer(stack);
    self.child.setFloating(false);

    std.log.debug("Set client {f} stack to {}", .{ self, stack });
}

pub fn setContainer(self: *Self, container: *LuaContainer) void {
    if (container.child.stack) |stack| {
        self.child.setContainer(stack);
        self.child.setFloating(false);

        std.log.debug("Set client {f} stack to {}", .{ self, stack });
    }
}

pub fn getFloating(self: *Self) bool {
    return self.child.floating;
}

pub fn setFloating(self: *Self, value: bool) void {
    self.child.setFloating(value);
}

pub fn close(self: *Self) void {
    self.child.close();
}

pub fn setModules(lua: *Lua) !i32 {
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
    LuaContext.pushT(lua, self, "Client");
}

pub fn hash(self: *const Self) usize {
    return @intFromPtr(self.child);
}
