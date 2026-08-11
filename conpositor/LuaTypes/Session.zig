const std = @import("std");
const zlua = @import("zlua");
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const Config = @import("../Config.zig");
const Layout = @import("../Layout.zig");
const Session = @import("../Session.zig");
const LuaContext = @import("../LuaContext.zig");

const LuaClosure = @import("Closure.zig");
const LuaTextModule = @import("TextModule.zig");
const LuaMonitor = @import("Monitor.zig");
const LuaRectangle = @import("Rectangle.zig");
const LuaContainer = @import("Container.zig");
const LuaClient = @import("Client.zig");
const LuaTag = @import("Tag.zig");
const LuaLayout = @import("Layout.zig");
const LuaClientFilter = @import("ClientFilter.zig");

const Lua = zlua.Lua;
const allocator = Config.allocator;

const Self = @This();

pub const Error = error{
    LuaMsgHandler,
    LuaRuntime,
    OutOfMemory,
};

pub const Event = enum { startup, add_monitor, mouse_move, mouse_release };

pub const MouseBindData = struct {
    mods: wlr.Keyboard.ModifierMask,
    button: u32,

    pub fn format(self: MouseBindData, writer: *std.Io.Writer) !void {
        if (self.mods.shift) try writer.writeAll("s+");
        if (self.mods.ctrl) try writer.writeAll("c+");
        if (self.mods.alt) try writer.writeAll("a+");
        if (self.mods.logo) try writer.writeAll("l+");

        try writer.print("{}", .{self.button});
    }
};

pub const BindData = struct {
    mods: wlr.Keyboard.ModifierMask,
    key: xkb.Keysym,

    pub fn format(self: BindData, writer: *std.Io.Writer) !void {
        if (self.mods.shift) try writer.writeAll("s+");
        if (self.mods.ctrl) try writer.writeAll("c+");
        if (self.mods.alt) try writer.writeAll("a+");
        if (self.mods.logo) try writer.writeAll("l+");

        var buffer: [128]u8 = undefined;
        const result = buffer[0..@intCast(self.key.getName(&buffer, 128))];

        try writer.writeAll(result);
    }
};

pub const PaletteColor = enum { border, background, foreground };

pub const FontInfo = struct {
    face: [:0]const u8,
    size: i32 = 12,

    pub fn format(self: FontInfo, writer: *std.Io.Writer) !void {
        try writer.print("{s} ({})", .{ self.face, self.size });
    }

    pub fn deinit(self: *FontInfo) void {
        allocator.free(self.face);
    }
};

font: FontInfo,
session: *Session,
title_pad: i32 = 3,
active_colors: std.EnumArray(PaletteColor, [4]f32) = .initFill(.{ 1, 1, 1, 1 }),
inactive_colors: std.EnumArray(PaletteColor, [4]f32) = .initFill(.{ 1, 1, 1, 1 }),
layouts: std.array_list.Managed(*Layout) = .init(allocator),
tags: std.array_list.Managed([:0]const u8) = .init(allocator),
binds: std.AutoHashMap(BindData, LuaClosure) = .init(allocator),
mouse_binds: std.AutoHashMap(MouseBindData, LuaClosure) = .init(allocator),

// TODO: better structure?
rules: std.array_list.Managed(struct { filter: LuaClientFilter, calls: LuaClosure }) = .init(allocator),

// TODO: Hash Map
events: std.array_list.Managed(struct { event: Event, calls: LuaClosure }) = .init(allocator),

pub fn getDebug() bool {
    return @import("builtin").mode == .Debug;
}

pub fn quit(self: *Self) !void {
    self.session.quit();
}

pub fn getTag(_: *Self, index: u8) ?LuaTag {
    return .{ .id = index - 1 };
}

pub fn getActiveClient(self: *Self) ?LuaClient {
    return .{
        .child = self.session.focusedClient() orelse return null,
    };
}

pub fn getActiveMonitor(self: *Self) ?LuaMonitor {
    return .{
        .child = self.session.focusedMonitor orelse return null,
    };
}

pub fn cycleFocus(self: *Self, dir: i32) !void {
    if (dir == 1)
        try self.session.focusStack(.forward)
    else if (dir == -1)
        try self.session.focusStack(.backward)
    else
        return error.BadCycleDirection;
}

// TODO: hide from lua
fn spawnThread(self: *Self, name: [:0]const u8, args: [][*:0]const u8) void {
    const argv = allocator.alloc([]const u8, args.len + 1) catch unreachable;

    argv[0] = @ptrCast(name);
    if (args.len > 0) {
        for (args, argv[1..]) |in, *out| {
            out.* = std.mem.span(in);
        }
    }

    const child = std.process.spawn(self.session.io, .{
        .argv = argv,
        .environ_map = self.session.environ_map,

        .pgid = 0,
        .stderr = .ignore,
        .stdout = .ignore,
        .stdin = .ignore,
    }) catch return;
    allocator.free(argv);

    _ = child;

    // At this point we dont care what the result is
    //_ = child.wait(self.session.io) catch undefined;
}

pub fn spawn(self: *Self, name: [:0]const u8, args: [][*:0]const u8) !void {
    const thread = try std.Thread.spawn(.{
        .allocator = allocator,
    }, spawnThread, .{ self, name, args });
    thread.detach();
}

pub fn setFont(self: *Self, face: []const u8, size: f32) !void {
    self.font.deinit();

    self.font = .{
        .face = try allocator.dupeZ(u8, face),
        .size = @intFromFloat(size),
    };

    std.log.debug("Set session font to {f}", .{self.font});
}

// TODO: move layout storage to lua
pub fn newLayout(self: *Self, name: []const u8) !LuaLayout {
    const container = try allocator.create(Layout.Container);

    container.* = .{
        .stack = null,
        .size = .{ .x_min = 0, .x_max = 1, .y_min = 0, .y_max = 1 },
        .children = &.{},
    };

    const layout = try allocator.create(Layout);

    layout.* = .{
        .name = try allocator.dupeZ(u8, name),
        .container = container,
    };

    try self.layouts.append(layout);

    return .{ .child = layout };
}

pub fn setColor(self: *Self, active: bool, palette_name: []const u8, color_name: []const u8) !void {
    var r: f32 = 1.0;
    var g: f32 = 1.0;
    var b: f32 = 1.0;
    var a: f32 = 1.0;

    if (color_name.len == 9) {
        if (color_name[0] != '#')
            return error.BadColor;

        const color = try std.fmt.parseInt(u32, color_name[1..], 16);
        r = @as(f32, @floatFromInt((color >> 24) & 0xff)) / 255;
        g = @as(f32, @floatFromInt((color >> 16) & 0xff)) / 255;
        b = @as(f32, @floatFromInt((color >> 8) & 0xff)) / 255;
        a = @as(f32, @floatFromInt((color >> 0) & 0xff)) / 255;
    } else if (color_name.len == 7) {
        if (color_name[0] != '#')
            return error.BadColor;

        const color = try std.fmt.parseInt(u32, color_name[1..], 16);
        r = @as(f32, @floatFromInt((color >> 16) & 0xff)) / 255;
        g = @as(f32, @floatFromInt((color >> 8) & 0xff)) / 255;
        b = @as(f32, @floatFromInt((color >> 0) & 0xff)) / 255;
        a = 1.0;
    } else return error.BadColor;

    const palette = std.meta.stringToEnum(PaletteColor, palette_name) orelse return error.BadLayer;

    if (active)
        self.active_colors.set(palette, .{ r, g, b, a })
    else
        self.inactive_colors.set(palette, .{ r, g, b, a });

    std.log.debug("Add color {s} to pallette {s} as the {s} color with rgba ({} {} {} {})", .{ color_name, palette_name, if (active) "active" else "inactive", r, g, b, a });

    try self.session.reloadColors();
}

pub fn addBind(lua: *Lua) !i32 {
    const old_top = lua.getTop();

    const self = lua.toAny(*Self, -4) catch lua.raiseErrorStr("Not a Session", .{});
    const mod_names = lua.toString(-3) catch lua.raiseErrorStr("Not a string", .{});
    const key_name = lua.toString(-2) catch lua.raiseErrorStr("Not a string", .{});
    const calls = lua.toAny(LuaClosure, -1) catch lua.raiseErrorStr("Not a closure", .{});
    errdefer calls.deinit();

    var mods: wlr.Keyboard.ModifierMask = .{};

    for (mod_names) |m| {
        switch (std.ascii.toLower(m)) {
            'c' => mods.ctrl = true,
            's' => mods.shift = true,
            'l' => mods.logo = true,
            'a' => mods.alt = true,
            else => {},
        }
    }

    {
        const key: BindData = .{
            .key = xkb.Keysym.fromName(key_name, .case_insensitive),
            .mods = mods,
        };

        if (try self.binds.fetchPut(key, calls)) |value|
            value.value.deinit();

        std.log.debug("Created bind for {any} {f}", .{ mods, key });
    }

    if (old_top != lua.getTop() + 0)
        return error.LuaError;

    return 0;
}

pub fn addMouseBind(lua: *Lua) !i32 {
    const old_top = lua.getTop();

    const self = lua.toAny(*Self, -4) catch lua.raiseErrorStr("Not a Session", .{});
    const mod_names = lua.toString(-3) catch lua.raiseErrorStr("Mods not a string", .{});
    const key_name = lua.toString(-2) catch lua.raiseErrorStr("Button not a string", .{});
    const calls = lua.toAny(LuaClosure, -1) catch lua.raiseErrorStr("Not a closure", .{});
    errdefer calls.deinit();

    var mods: wlr.Keyboard.ModifierMask = .{};

    for (mod_names) |m| {
        switch (std.ascii.toLower(m)) {
            'c' => mods.ctrl = true,
            's' => mods.shift = true,
            'l' => mods.logo = true,
            'a' => mods.alt = true,
            else => {},
        }
    }

    const button: u32 = if (std.mem.eql(u8, key_name, "Left"))
        272
    else if (std.mem.eql(u8, key_name, "Right"))
        273
    else
        return error.InvalidMouseButton;

    const key: MouseBindData = .{
        .button = button,
        .mods = mods,
    };

    if (try self.mouse_binds.fetchPut(key, calls)) |value|
        value.value.deinit();

    std.log.debug("Set mouse bind for {f}", .{key});

    if (old_top != lua.getTop() + 0)
        return error.LuaError;

    return 0;
}

pub fn addRule(lua: *Lua) !i32 {
    const old_top = lua.getTop();

    const self = lua.toAny(*Self, -3) catch lua.raiseErrorStr("Not a Session", .{});
    const filter = lua.toAny(LuaClientFilter, -2) catch lua.raiseErrorStr("Not a lua filter", .{});
    const calls = lua.toAny(LuaClosure, -1) catch lua.raiseErrorStr("Not a closure", .{});
    errdefer calls.deinit();

    try self.rules.append(.{
        .filter = filter,
        .calls = calls,
    });

    if (old_top != lua.getTop() + 0)
        return error.LuaError;

    return 0;
}

pub fn addHook(lua: *Lua) !i32 {
    const old_top = lua.getTop();

    const self = lua.toAny(*Self, -3) catch lua.raiseErrorStr("Not a Session", .{});
    const event_name = lua.toString(-2) catch lua.raiseErrorStr("Not a string", .{});
    const calls = lua.toAny(LuaClosure, -1) catch lua.raiseErrorStr("Not a closure", .{});
    errdefer calls.deinit();

    const event_id = std.meta.stringToEnum(Event, event_name) orelse return error.BadEventName;

    try self.events.append(.{
        .event = event_id,
        .calls = calls,
    });

    if (old_top != lua.getTop() + 0)
        return error.LuaError;

    return 0;
}

pub fn sendEvent(self: *Self, comptime T: type, lua: *Lua, event_id: Event, data: T) Error!bool {
    //var result = false;
    for (self.events.items) |event| {
        if (event.event != event_id)
            continue;

        _ = try lua.pushAny(event.calls);
        _ = try lua.pushAny(data);
        lua.protectedCall(.{ .args = 1, .results = 0 }) catch |err| {
            const result = lua.toString(-1) catch "unknown lua error";
            lua.pop(1);

            std.log.err("{s}: {s}", .{ @errorName(err), result });

            //result = result or lua.toBoolean(-1);
        };
    }

    return true;
}

pub fn format(_: Self, writer: *std.Io.Writer) !void {
    try writer.print("Session", .{});
}

pub fn deinit(self: *Self) void {
    for (self.layouts.items) |layout|
        layout.deinit();

    for (self.rules.items) |rule| {
        rule.filter.deinit();
        rule.calls.deinit();
    }

    for (self.events.items) |event|
        event.calls.deinit();

    for (self.tags.items) |tag|
        allocator.free(tag);

    {
        var iter = self.mouse_binds.iterator();
        while (iter.next()) |item| {
            item.value_ptr.deinit();
        }
    }

    {
        var iter = self.binds.iterator();
        while (iter.next()) |item| {
            item.value_ptr.deinit();
        }
    }

    self.layouts.deinit();
    self.tags.deinit();
    self.binds.deinit();
    self.mouse_binds.deinit();
    self.rules.deinit();
    self.events.deinit();
    self.font.deinit();
}

pub fn hash(_: *const Self) usize {
    // This is a singleton
    return 0;
}
