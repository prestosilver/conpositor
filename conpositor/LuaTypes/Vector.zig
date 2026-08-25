const std = @import("std");
const zlua = @import("zlua");

const Closure = @import("Closure.zig");

const Lua = zlua.Lua;

const Self = @This();

x: f64,
y: f64,

pub fn fromLua(lua: *Lua, _: ?std.mem.Allocator, index: i32) !Self {
    _ = lua.getField(index, "x");
    const x = lua.toNumber(f64, -1) catch 0;
    lua.pop(1);

    _ = lua.getField(index, "y");
    const y = lua.toNumber(f64, -1) catch 0;
    lua.pop(1);

    return .{
        .x = x,
        .y = y,
    };
}

pub fn toLua(self: Self, lua: *Lua) void {
    lua.newTable();
    lua.pushNumber(self.x);
    lua.setField(-2, "x");
    lua.pushNumber(self.y);
    lua.setField(-2, "y");
}
