const std = @import("std");

const allocator = @import("../Config.zig").allocator;

const zlua = @import("zlua");
const Lua = zlua.Lua;

const Self = @This();

ref: i32,
upvs: []i32,
lua: *Lua,

pub fn deinit(self: Self) void {
    allocator.free(self.upvs);
    self.lua.unref(zlua.registry_index, self.ref);

    std.log.debug("Unref lua closure#{}", .{self.ref});
}

pub fn format(self: Self, writer: *std.Io.Writer) !void {
    try writer.print("Closure#{}", .{self.ref});
}

pub fn fromLua(lua: *Lua, _: ?std.mem.Allocator, index: i32) !Self {
    if (!lua.isFunction(index)) return error.LuaError;

    lua.pushValue(index); // func
    const r = lua.ref(zlua.registry_index);

    var info: zlua.DebugInfo = undefined;
    lua.pushValue(index); // func
    lua.getInfo(.{ .@">" = true, .u = true }, &info);

    const upvs = try allocator.alloc(i32, info.num_upvalues);
    for (1..info.num_upvalues + 1) |v| {
        _ = try lua.getUpvalue(index, @intCast(v)); // func table upv
        upvs[v - 1] = lua.ref(zlua.registry_index);
    }

    std.log.debug("Ref lua Closure#{}", .{r});

    return .{
        .lua = lua,
        .ref = r,
        .upvs = upvs,
    };
}

pub fn toLua(self: Self, lua: *Lua) void {
    _ = lua.getIndexRaw(zlua.registry_index, self.ref);
}
