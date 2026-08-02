const std = @import("std");
const zlua = @import("zlua");

const Config = @import("../Config.zig");

const Lua = zlua.Lua;

const Self = @This();

x: f64,
y: f64,
width: f64,
height: f64,

pub fn fromLua(lua: *Lua, _: ?std.mem.Allocator, index: i32) !Self {
    const top = lua.getTop();
    defer lua.setTop(top);

    lua.pushValue(index);

    _ = lua.getField(-1, "x");
    const x = lua.toNumber(-1) catch 0;
    lua.pop(1);

    _ = lua.getField(-1, "y");
    const y = lua.toNumber(-1) catch 0;
    lua.pop(1);

    _ = lua.getField(-1, "width");
    const w = lua.toNumber(-1) catch 0;
    lua.pop(1);

    _ = lua.getField(-1, "height");
    const h = lua.toNumber(-1) catch 0;
    lua.pop(1);

    return .{
        .x = x,
        .y = y,
        .width = w,
        .height = h,
    };
}

pub fn toLua(self: Self, lua: *Lua) void {
    lua.newTable();
    lua.pushNumber(self.x);
    lua.setField(-2, "x");
    lua.pushNumber(self.y);
    lua.setField(-2, "y");
    lua.pushNumber(self.width);
    lua.setField(-2, "width");
    lua.pushNumber(self.height);
    lua.setField(-2, "height");
}
