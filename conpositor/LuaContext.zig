// This is an abstraction over zlua that allows for cleaner automated
// oop bindings.
//
// NOTES:
// If this is implemented properly zlua should not be imported by anything
//      outside of this and LuaTypes
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
    result: ?[:0]const u8,

    pub fn deinit(self: *RunResult) void {
        if (self.result) |result|
            allocator.free(result);
    }
};

pub const LuaType = struct {
    const LuaParam = struct {
        name: []const u8 = "",
        kind: []const u8 = "",
        desc: []const u8 = "",
    };

    const LuaMethod = struct {
        impl_name: []const u8,
        lua_name: [:0]const u8,
        description: []const u8,

        params: []const LuaParam = &.{},
        returns: ?LuaParam = null,

        binding_mode: enum { raw, auto },
        kind: enum { function, method, getter, setter, hidden_function } = .method,
    };

    impl: type,
    lua_name: [:0]const u8,
    description: []const u8,
    methods: []const LuaMethod,
    gc: ?LuaMethod = null,

    // Registers a type with a zlua context
    pub inline fn addTo(comptime self: LuaType, lua: *Lua) Error!void {
        _ = lua.getGlobal("_GenerateType");

        // the function table
        lua.newTable();

        // the method table
        lua.newTable();

        lua.autoPushFunction(self.impl.hash);
        lua.setField(-2, "_hash");

        // the getter table
        lua.newTable();

        // the setter table
        lua.newTable();

        inline for (self.methods) |method| {
            const index = switch (method.kind) {
                .function, .hidden_function => -5,
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

        lua.protectedCall(.{ .args = 4, .results = 1 }) catch |err| {
            std.log.err("{s} Error: {s}", .{ @errorName(err), lua.toString(-1) catch "unknown" });
            lua.pop(1);
        };

        if (self.gc) |gc_method| {
            switch (gc_method.binding_mode) {
                .raw => {
                    lua.pushFunction(@field(self.impl, gc_method.impl_name));
                    lua.setField(-2, "__gc");
                },
                .auto => {
                    lua.autoPushFunction(@field(self.impl, gc_method.impl_name));
                    lua.setField(-2, "__gc");
                },
            }
        }

        const MetaMethods = struct {
            fn eq(a: self.impl, b: self.impl) bool {
                return a.hash() == b.hash();
            }

            pub fn toString(tmp_lua: *Lua) !c_int {
                const a = try tmp_lua.toAny(*self.impl, -1);

                // panics on out of memory
                const pushes = try std.fmt.allocPrint(allocator, "{f}", .{a});
                defer allocator.free(pushes);

                tmp_lua.pop(1);

                _ = tmp_lua.pushString(pushes);

                return 1;
            }
        };

        if (@hasDecl(self.impl, "fromLua")) {
            lua.autoPushFunction(MetaMethods.eq);
            lua.setField(-2, "__eq");
        }
        lua.pushFunction(zlua.wrap(MetaMethods.toString));
        lua.setField(-2, "__tostring");

        lua.setGlobal(self.lua_name);
    }
};

// TODO: Extract LUA_TYPES into the LuaTypes folder
pub const LUA_TYPES = [_]LuaType{
    .{
        .impl = @import("LuaTypes/TextModule.zig"),
        .lua_name = "TextModule",
        .description =
        \\A text module for client bars
        ,
        .gc = .{
            .impl_name = "luaGC",
            .lua_name = "__gc",
            .description = "Frees",
            .binding_mode = .auto,
            .kind = .hidden_function,
        },
        .methods = &.{
            .{
                .impl_name = "new",
                .lua_name = "new",
                .description = "Creates a new text module",

                .params = &.{
                    .{ .name = "text", .kind = "fun(base: any):string", .desc = "The callback used to get the modules text" },
                },
                .returns = .{ .name = "module", .kind = "TextModule", .desc = "A new text module" },

                .binding_mode = .auto,
                .kind = .function,
            },
        },
    },
    .{
        .impl = @import("LuaTypes/Client.zig"),
        .lua_name = "Client",
        .description =
        \\A client object
        ,
        .methods = &.{
            .{
                .impl_name = "getPosition",
                .lua_name = "position",
                .description = "Gets the clients position",

                .returns = .{ .kind = "Vector2" },

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "setPosition",
                .lua_name = "position",
                .description = "Sets the clients position",

                .returns = .{ .kind = "Vector2" },

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "getFullscreen",
                .lua_name = "fullscreen",
                .description = "Gets the fullscreen state of the client",

                .returns = .{ .kind = "boolean" },

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "setFullscreen",
                .lua_name = "fullscreen",
                .description = "Sets the fullscreen state of the client",

                .returns = .{ .kind = "boolean" },

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "setBorder",
                .lua_name = "border",
                .description = "Sets the border width of the client",

                .returns = .{ .kind = "number" },

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "getAppid",
                .lua_name = "appid",
                .description = "Gets the clients appid",

                .returns = .{ .kind = "string" },

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "getTitle",
                .lua_name = "title",
                .description = "Gets the clients title",

                .returns = .{ .kind = "string" },

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "setTag",
                .lua_name = "tag",
                .description = "Sets the clients tag",

                .returns = .{ .kind = "Tag" },

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "setMonitor",
                .lua_name = "monitor",
                .description = "Sets the clients monitor",

                .returns = .{ .kind = "Monitor" },

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "getStack",
                .lua_name = "stack",
                .description = "Gets the clients stack",

                .returns = .{ .kind = "Stack" },

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

                .returns = .{ .kind = "boolean" },

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
    .{
        .impl = @import("LuaTypes/Tag.zig"),
        .lua_name = "Tag",
        .description =
        \\A tag object
        ,
        .methods = &.{},
    },
    .{
        .impl = @import("LuaTypes/Monitor.zig"),
        .lua_name = "Monitor",
        .description =
        \\A monitor object
        ,
        .methods = &.{
            .{
                .impl_name = "getPosition",
                .lua_name = "position",
                .description = "Gets the position of a monitor",

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "getActiveTag",
                .lua_name = "active_tag",
                .description = "Gets the active tag of the monitor",

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "setActiveTag",
                .lua_name = "active_tag",
                .description = "Sets the active tag of the monitor",

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "getLayout",
                .lua_name = "layout",
                .description = "Gets the layout of the monitor",

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "setLayout",
                .lua_name = "layout",
                .description = "Sets the layout of the monitor",

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "setInnerGaps",
                .lua_name = "inner_gaps",
                .description = "Sets the inner gaps of the monitor",

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "setOuterGaps",
                .lua_name = "outer_gaps",
                .description = "Sets the outer gaps of the monitor",

                .binding_mode = .auto,
                .kind = .setter,
            },
        },
    },
    .{
        .impl = @import("LuaTypes/Session.zig"),
        .lua_name = "Session",
        .description =
        \\The session object
        ,
        .methods = &.{
            .{
                .impl_name = "getDebug",
                .lua_name = "debug",
                .description = "True if inside a debug build",

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "getTag",
                .lua_name = "_get_tag",
                .description = "Returns the tag at index",

                .binding_mode = .auto,
                .kind = .hidden_function,
            },
            .{
                .impl_name = "quit",
                .lua_name = "quit",
                .description = "Quit the current session",

                .binding_mode = .auto,
            },
            .{
                .impl_name = "getActiveClient",
                .lua_name = "active_client",
                .description = "Returns the current active client",

                .binding_mode = .auto,
            },
            .{
                .impl_name = "getActiveMonitor",
                .lua_name = "active_monitor",
                .description = "Gets the active monitor",

                .params = &.{},
                .returns = .{ .name = "monitor", .kind = "Monitor", .desc = "The active monitor" },

                .binding_mode = .auto,
            },
            .{
                .impl_name = "cycleFocus",
                .lua_name = "cycle_focus",
                .description = "Cycles the current stack",

                .params = &.{
                    .{ .name = "dir", .kind = "-1|1", .desc = "The direction to cycle" },
                },

                .binding_mode = .auto,
            },
            .{
                .impl_name = "spawn",
                .lua_name = "spawn",
                .description = "Spawns a child process",

                .params = &.{
                    .{ .name = "command", .kind = "string", .desc = "The command to spawn" },
                    .{ .name = "...", .kind = "string", .desc = "The parameters for the command" },
                },

                .binding_mode = .auto,
            },
            .{
                .impl_name = "setFont",
                .lua_name = "set_font",
                .description = "Sets the sessions font",

                .params = &.{
                    .{ .name = "face", .kind = "string", .desc = "The font face to use" },
                    .{ .name = "size", .kind = "number", .desc = "The size to set" },
                },

                .binding_mode = .auto,
            },
            .{
                .impl_name = "newLayout",
                .lua_name = "new_layout",
                .description = "Creates a new layout",

                .params = &.{
                    .{ .name = "name", .kind = "string", .desc = "The name of the new layout" },
                },
                .returns = .{ .name = "layout", .kind = "Layout", .desc = "The created layout" },

                .binding_mode = .auto,
            },
            .{
                .impl_name = "setColor",
                .lua_name = "set_color",
                .description = "Sets a palette color",

                .binding_mode = .auto,
            },
            .{
                .impl_name = "addBind",
                .lua_name = "bind",
                .description = "Adds a key bind",

                .params = &.{
                    .{ .name = "modifiers", .kind = "string", .desc = "The mod keys in the bind" },
                    .{ .name = "key", .kind = "string", .desc = "The key to be bound" },
                    .{ .name = "callback", .kind = "fun()", .desc = "The callback to run" },
                },

                .binding_mode = .raw,
            },
            .{
                .impl_name = "addMouseBind",
                .lua_name = "mouse_bind",
                .description = "Adds a mouse bind",

                .params = &.{
                    .{ .name = "modifiers", .kind = "string", .desc = "The mod keys in the bind" },
                    .{ .name = "button", .kind = "string", .desc = "The button to be bound" },
                    .{ .name = "callback", .kind = "fun(client: Client, position: Vector2)", .desc = "The callback to run" },
                },

                .binding_mode = .raw,
            },
            .{
                .impl_name = "addRule",
                .lua_name = "add_rule",
                .description = "Adds a client rule",

                .params = &.{
                    .{ .name = "traits", .kind = "any", .desc = "The required client traits" },
                    .{ .name = "callback", .kind = "fun(client:Client)", .desc = "The callback to run" },
                },

                .binding_mode = .raw,
            },
            .{
                .impl_name = "addHook",
                .lua_name = "hook",
                .description = "Adds a hook to the current session",

                .binding_mode = .raw,
            },
        },
    },
    .{
        .impl = @import("LuaTypes/Container.zig"),
        .lua_name = "Container",
        .description =
        \\A container object
        ,
        .methods = &.{
            .{
                .impl_name = "setStack",
                .lua_name = "stack",
                .description = "Sets the stack to display in the container",

                .binding_mode = .auto,
                .kind = .setter,
            },
            .{
                .impl_name = "addChild",
                .lua_name = "add_child",
                .description = "Adds a child stack to the stack",

                .binding_mode = .auto,
            },
        },
    },
    .{
        .impl = @import("LuaTypes/Layout.zig"),
        .lua_name = "Layout",
        .description =
        \\A layout object
        ,
        .methods = &.{
            .{
                .impl_name = "getRoot",
                .lua_name = "root",
                .description = "Gets the root container of the layout",

                .binding_mode = .auto,
                .kind = .getter,
            },
            .{
                .impl_name = "getName",
                .lua_name = "name",
                .description = "Gets the name of the layout",

                .binding_mode = .auto,
                .kind = .getter,
            },
        },
    },
};

is_init: bool = false,
lua: *Lua = undefined,
session: LuaSession,

// Used to push an instance onto the stack
// TODO: break out the impl into a function in type_gen.lua
pub fn pushT(lua: *Lua, self: anytype, name: [:0]const u8) void {
    const instance = lua.newUserdata(@TypeOf(self), 0);
    instance.* = self;

    _ = lua.getGlobal(name);
    lua.setMetatable(-2);
}

// Transmits a hook event from Conpositor->lua
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
        const result = try allocator.dupeZ(u8, self.lua.toString(-1) catch "unknown lua error");

        std.log.err("{s}: {s}", .{ @errorName(err), result });

        var idx: i32 = 1;
        while (self.lua.getStack(idx) catch null) |di| : (idx += 1) {
            var tmp = di;

            self.lua.getInfo(.{ .n = true }, &tmp);
            std.log.info("{?s}", .{di.name});
        }

        self.lua.setTop(0);

        return .{
            .failed = true,
            .result = result,
        };
    };

    var result: ?[:0]const u8 = null;

    if (self.lua.getTop() > 0) {
        result = try allocator.dupeZ(u8, self.lua.toString(-1) catch "");
        self.lua.setTop(0);
    }

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

    self.lua.doString(@embedFile("lua/type_gen.lua")) catch unreachable;

    inline for (LUA_TYPES) |lua_type|
        try lua_type.addTo(self.lua);

    self.lua.pushLightUserdata(&self.session);

    _ = self.lua.getGlobal("Session");
    self.lua.setMetatable(-2);

    self.lua.setGlobal("session");

    // mixins
    self.lua.doString(@embedFile("lua/session_mixin.lua")) catch unreachable;

    self.is_init = true;

    std.log.info("Init lua state", .{});
}

pub fn deinit(self: *Self) void {
    self.session.deinit();
    self.lua.deinit();

    self.is_init = false;
}

pub fn destroy(self: *Self, kind: [:0]const u8, base: anytype) void {
    if (!self.is_init) return;

    _ = self.lua.getGlobal(kind);
    _ = self.lua.getField(-1, "_destroy");
    self.lua.pushAny(base) catch unreachable;
    self.lua.protectedCall(.{ .args = 1, .results = 0 }) catch unreachable;
    _ = self.lua.pop(1);
}
