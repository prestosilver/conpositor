const std = @import("std");
const zlua = @import("zlua");

const LuaSession = @import("LuaTypes/Session.zig");
const LuaClient = @import("LuaTypes/Client.zig");
const LuaVector = @import("LuaTypes/Vector.zig");

const Config = @import("Config.zig");
const Client = @import("Client.zig");

const allocator = Config.allocator;

const Lua = zlua.Lua;

const Self = @This();

pub const Error = error{
    Unimplemented,
    OutOfMemory,
    KeyInRegistry,
    LuaMsgHandler,
    LuaRuntime,
};

pub const RunResult = struct {
    failed: bool,
    result: [:0]const u8,

    pub fn deinit(self: *RunResult) void {
        allocator.free(self.result);
    }
};

pub const LuaType = struct {
    const LuaMethod = struct {
        impl_name: []const u8,
        lua_name: [:0]const u8,
        description: []const u8,

        binding_mode: enum { raw, auto },
        kind: enum { method, getter, setter } = .method,
    };

    impl: type,
    lua_name: [:0]const u8,
    description: []const u8,
    methods: []const LuaMethod,
    gc: ?LuaMethod = null,

    pub inline fn addTo(comptime self: LuaType, lua: *Lua) Error!void {
        _ = lua.getGlobal("_GenerateType");

        // the method table
        lua.newTable();

        // the getter table
        lua.newTable();

        // the setter table
        lua.newTable();

        inline for (self.methods) |method| {
            const index = switch (method.kind) {
                .method => -4,
                .getter => -3,
                .setter => -2,
            };

            switch (method.binding_mode) {
                .raw => {
                    const field_value = @field(self.impl, method.impl_name);
                    const field_type = @TypeOf(field_value);
                    const field_info = @typeInfo(field_type);
                    switch (field_info) {
                        .@"fn" => {
                            lua.pushFunction(zlua.wrap(field_value));
                            lua.setField(index, method.lua_name);
                        },
                        else => @compileError("Invalid raw type " ++ @typeName(field_type)),
                    }
                },
                .auto => {
                    const new_name = method.lua_name;

                    const field_value = @field(self.impl, method.impl_name);
                    const field_type = @TypeOf(field_value);
                    const field_info = @typeInfo(field_type);
                    switch (field_info) {
                        .@"fn" => {
                            lua.autoPushFunction(field_value);
                            lua.setField(index, new_name);
                        },
                        else => @compileError("Invalid auto type " ++ @typeName(field_type)),
                    }
                },
            }
        }

        lua.protectedCall(.{ .args = 3, .results = 1 }) catch |err| {
            std.log.err("{s} Error: {s}", .{ @errorName(err), lua.toString(-1) catch "unknown" });
            lua.pop(1);
        };

        if (self.gc) |gc_method| {
            switch (gc_method.binding_mode) {
                .raw => {
                    lua.autoPushFunction(@field(self.impl, gc_method.impl_name));
                    lua.setField(-2, "__gc");
                },
                .auto => {
                    lua.pushFunction(@field(self.impl, gc_method.impl_name));
                    lua.setField(-2, "__gc");
                },
                .setter, .setter => @compileError("gc method cannot be of type" ++ @tagName(gc_method.binding_mode)),
            }
        }

        if (@hasDecl(self.impl, "fromLua")) {
            const Compare = struct {
                fn eq(a: self.impl, b: self.impl) bool {
                    return std.meta.eql(a, b);
                }
            };
            lua.autoPushFunction(Compare.eq);
            lua.setField(-2, "__eq");
        }

        lua.setGlobal(self.lua_name);
    }
};

pub const LUA_TYPES = [_]LuaType{
    .{
        .impl = @import("LuaTypes/Client.zig"),
        .lua_name = "Client",
        .description =
        \\ A client object
        ,
        .methods = &.{
            .{
                .impl_name = "getPosition",
                .lua_name = "position",
                .description = "Gets the clients position",

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "setPosition",
                .lua_name = "position",
                .description = "Sets the clients position",

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "getFullscreen",
                .lua_name = "fullscreen",
                .description = "Gets the fullscreen state of the client",

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "setFullscreen",
                .lua_name = "fullscreen",
                .description = "Sets the fullscreen state of the client",

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "setBorder",
                .lua_name = "border",
                .description = "Sets the border width of the client",

                .binding_mode = .auto,
                .kind = .setter,
            },
            // .{
            //     .impl_name = "setIcon",
            //     .lua_name = "icon",
            //     .description = "Sets the icon of the client",

            //     .binding_mode = .auto,
            //     .kind = .setter,
            // },
            // .{
            //     .impl_name = "getIcon",
            //     .lua_name = "icon",
            //     .description = "Sets the icon of the client",

            //     .binding_mode = .auto,
            //     .kind = .getter,
            // },
            .{
                .impl_name = "setLabel",
                .lua_name = "label",
                .description = "Sets a label for the client",

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "getLabel",
                .lua_name = "label",
                .description = "Gets a label for the client",

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "getAppid",
                .lua_name = "appid",
                .description = "Gets the clients appid",

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "getTitle",
                .lua_name = "title",
                .description = "Gets the clients title",

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "setTag",
                .lua_name = "tag",
                .description = "Sets the clients tag",

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "setMonitor",
                .lua_name = "monitor",
                .description = "Sets the clients monitor",

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "getStack",
                .lua_name = "stack",
                .description = "Gets the clients stack",

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "setStack",
                .lua_name = "stack",
                .description = "Sets the clients stack",

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "setContainer",
                .lua_name = "container",
                .description = "Sets the clients container",

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "setFloating",
                .lua_name = "floating",
                .description = "Sets the clients floating state",

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "getFloating",
                .lua_name = "floating",
                .description = "Gets the clients floating state",

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "close",
                .lua_name = "close",
                .description = "Closes the client",

                .binding_mode = .auto,
            },
            .{
                .impl_name = "setModules",
                .lua_name = "modules",
                .description = "Sets the clients modules",

                .binding_mode = .raw,
                .kind = .setter,
            },
        },
    },
};

lua: *Lua = undefined,
session: LuaSession,

pub fn pushT(lua: *Lua, self: anytype, name: [:0]const u8) void {
    lua.newTable();

    const instance = lua.newUserdata(@TypeOf(self), 0);
    instance.* = self;
    lua.setField(-2, "instance");

    lua.newTable();
    lua.setField(-2, "fields");

    _ = lua.getGlobal(name);
    lua.setMetatable(-2);
}

fn roFunction() !void {
    return error.AssignToReadOnly;
}

// TODO: Dont force snake case here
inline fn globalType(lua: *Lua, comptime T: type, name: [:0]const u8) Error!void {
    const info = @typeInfo(T.LuaMethods);

    if (info != .@"struct") @compileError("expected struct for pushtype");

    // create my method table
    lua.newTable();

    inline for (info.@"struct".decls) |decl| {
        if (comptime std.mem.startsWith(u8, decl.name, "raw_")) {
            const new_name = decl.name[4..];

            const field_value = @field(T.LuaMethods, decl.name);
            const field_type = @TypeOf(field_value);
            const field_info = @typeInfo(field_type);
            switch (field_info) {
                .@"fn" => {
                    lua.pushFunction(zlua.wrap(field_value));
                    lua.setField(-2, new_name);
                },
                else => {},
            }
        } else {
            const new_name = decl.name;

            const field_value = @field(T.LuaMethods, decl.name);
            const field_type = @TypeOf(field_value);
            const field_info = @typeInfo(field_type);
            switch (field_info) {
                .@"fn" => {
                    lua.autoPushFunction(field_value);
                    lua.setField(-2, new_name);
                },
                else => {},
            }
        }
    }

    lua.newTable();
    lua.autoPushFunction(roFunction);
    lua.setField(-2, "__new_index");
    lua.setMetatable(-2);

    try lua.newMetatable(name);
    lua.pushValue(-2);
    lua.setField(-2, "__index");

    if (@hasDecl(T, "luaGC")) {
        lua.autoPushFunction(T.luaGC);
        lua.setField(-2, "__gc");
    }

    if (@hasDecl(T, "fromLua")) {
        const Compare = struct {
            fn eq(a: T, b: T) bool {
                return std.meta.eql(a, b);
            }
        };
        lua.autoPushFunction(Compare.eq);
        lua.setField(-2, "__eq");
    }
    lua.pop(1);

    lua.setGlobal(name);
}

pub fn sendEvent(self: *Self, comptime T: type, event_id: LuaSession.Event, data: T) Error!bool {
    return self.session.sendEvent(T, self.lua, event_id, data);
}

pub fn runFile(self: *Self, file: [:0]const u8) Error!void {
    self.lua.doFile(file) catch |err| {
        const result = self.lua.toString(-1) catch "unknown lua error";
        defer self.lua.pop(1);

        std.log.err("{s}: {s}", .{ @errorName(err), result });

        var idx: i32 = 1;
        while (self.lua.getStack(idx) catch null) |di| : (idx += 1) {
            var tmp = di;

            self.lua.getInfo(.{ .n = true }, &tmp);
            std.log.info("{?s}", .{di.name});
        }
    };
}

pub fn run(self: *Self, command: []const u8) Error!RunResult {
    const cmd = try allocator.dupeZ(u8, command);
    defer allocator.free(cmd);

    self.lua.doString(cmd) catch |err| {
        const result = self.lua.toString(-1) catch "unknown lua error";

        std.log.err("{s}: {s}", .{ @errorName(err), result });

        var idx: i32 = 1;
        while (self.lua.getStack(idx) catch null) |di| : (idx += 1) {
            var tmp = di;

            self.lua.getInfo(.{ .n = true }, &tmp);
            std.log.info("{?s}", .{di.name});
        }

        return .{
            .failed = true,
            .result = result,
        };
    };

    const result = try allocator.dupeZ(u8, self.lua.toString(-1) catch "");
    self.lua.pop(1);

    return .{
        .failed = false,
        .result = result,
    };
}

pub fn applyRules(self: *Self, client: *Client) !void {
    const lua = self.lua;

    const appid = client.getAppId();
    const title = client.getTitle();

    for (self.session.rules.items) |rule| {
        if (rule.filter.matches(title, appid)) {
            try lua.pushAny(rule.calls);
            try lua.pushAny(LuaClient{ .child = client });
            lua.protectedCall(.{ .args = 1, .results = 0 }) catch |err| {
                std.log.err("{s} Error: {s}", .{ @errorName(err), self.lua.toString(-1) catch "unknown" });
                self.lua.pop(1);
            };
        }
    }
}

pub fn mouseBind(self: *Self, bind: LuaSession.MouseBindData, pos: LuaVector, client: ?*Client) !bool {
    const lua = self.lua;

    const clientArg: ?LuaClient = if (client) |child| .{ .child = child } else null;

    if (self.session.mouse_binds.get(bind)) |bind_call| {
        try lua.pushAny(bind_call);
        try lua.pushAny(clientArg);
        try lua.pushAny(pos);
        lua.protectedCall(.{ .args = 2, .results = 0 }) catch |err| {
            std.log.err("{s} Error: {s}", .{ @errorName(err), self.lua.toString(-1) catch "unknown" });
            lua.pop(1);

            return false;
        };

        return true;
    }

    return false;
}

pub fn keyBind(self: *Self, bind: LuaSession.BindData) !bool {
    const lua = self.lua;

    if (self.session.binds.get(bind)) |bind_call| {
        try lua.pushAny(bind_call);
        lua.protectedCall(.{ .args = 0, .results = 0 }) catch |err| {
            std.log.err("{s} Error: {s}", .{ @errorName(err), self.lua.toString(-1) catch "unknown" });
            lua.pop(1);

            return false;
        };

        return true;
    }

    return false;
}

pub fn init(self: *Self, path: []const u8) Error!void {
    self.lua = try Lua.init(allocator);

    self.lua.openLibs();

    _ = self.lua.getGlobal("package");

    _ = self.lua.pushString(path);
    self.lua.setField(-2, "path");
    self.lua.pop(1);

    self.lua.doString(@embedFile("type_gen.lua")) catch unreachable;

    inline for (LUA_TYPES) |lua_type|
        try lua_type.addTo(self.lua);

    try globalType(self.lua, @import("LuaTypes/Session.zig"), "Session");
    try globalType(self.lua, @import("LuaTypes/Container.zig"), "Container");
    try globalType(self.lua, @import("LuaTypes/Layout.zig"), "Layout");
    try globalType(self.lua, @import("LuaTypes/Monitor.zig"), "Monitor");
    try globalType(self.lua, @import("LuaTypes/Stack.zig"), "Stack");
    try globalType(self.lua, @import("LuaTypes/Tag.zig"), "Tag");
    try globalType(self.lua, @import("LuaTypes/ClientFilter.zig"), "ClientFilter");
    try globalType(self.lua, @import("LuaTypes/TextModule.zig"), "TextModule");

    try self.lua.pushAny(&self.session);
    self.lua.setMetatableRegistry("Session");
    self.lua.setGlobal("session");

    std.log.info("Init lua state", .{});
}

pub fn deinit(self: *Self) void {
    self.session.deinit();
    self.lua.deinit();
}
