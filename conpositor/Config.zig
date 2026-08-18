// Config is used as the interface between LuaContext and the session instance
// This allows for lua to be swapped out on the chance I would later like to,
// or the ability to switch to luajit for increased preformance if that becomes
// an issue.
//
// NOTES:
// If this is implemented properly nothing else should import LuaContext
const std = @import("std");
const zlua = @import("zlua");
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");
const c = @import("c.zig").c;
const known_folders = @import("known-folders");

const LuaContext = @import("LuaContext.zig");

// TODO: since lua context is an abstraction over lua this should not import these
const LuaClient = @import("LuaTypes/Client.zig");
const LuaSession = @import("LuaTypes/Session.zig");
const LuaVector = @import("LuaTypes/Vector.zig");

const Layout = @import("Layout.zig");
const Session = @import("Session.zig");
const Client = @import("Client.zig");
const Monitor = @import("Monitor.zig");

const Config = @This();

pub const Error = LuaContext.Error || known_folders.Error;

pub const allocator_data = if (@import("builtin").mode == .Debug) struct {
    var gpa: std.heap.DebugAllocator(.{
        .thread_safe = true,
        .stack_trace_frames = 20,
    }) = .{};
    pub const allocator = gpa.allocator();

    pub fn deinit() void {
        if (gpa.deinit() == .ok)
            std.log.debug("no leaks! :)", .{});
    }
} else struct {
    pub const allocator = std.heap.c_allocator;

    pub fn deinit() void {}
};

pub const allocator = allocator_data.allocator;

// TODO: Lua context should not be owned by config
lua: LuaContext,

io: std.Io,
environ_map: *const std.process.Environ.Map,
home_path: []const u8 = undefined,

// from river:
// https://github.com/riverwm/river/blob/46f77f30dcce06b7af0ec8dff5ae3e4fbc73176f/river/process.zig
fn cleanupChild() void {
    if (c.setsid() < 0) unreachable;
    if (std.posix.system.sigprocmask(std.posix.SIG.SETMASK, &std.posix.sigemptyset(), null) < 0) unreachable;

    const sig_dfl = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.DFL },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.PIPE, &sig_dfl, null);

    if (original_rlimit) |original| {
        std.posix.setrlimit(.NOFILE, original) catch {
            std.log.err("failed to restore original file descriptor limit for " ++
                "child process, setrlimit failed", .{});
        };
    }
}

var original_rlimit: ?std.posix.rlimit = null;

pub fn init(self: *Config) Error!void {
    // also https://github.com/riverwm/river/blob/46f77f30dcce06b7af0ec8dff5ae3e4fbc73176f/river/process.zig
    const sig_ign = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.PIPE, &sig_ign, null);

    // Most unix systems have a default limit of 1024 file descriptors and it
    // seems unlikely for this default to be universally raised due to the
    // broken behavior of select() on fds with value >1024. However, it is
    // unreasonable to use such a low limit for a process such as river which
    // uses many fds in its communication with wayland clients and the kernel.
    //
    // There is however an advantage to having a relatively low limit: it helps
    // to catch any fd leaks. Therefore, don't use some crazy high limit that
    // can never be reached before the system runs out of memory. This can be
    // raised further if anyone reaches it in practice.
    if (std.posix.getrlimit(.NOFILE)) |original| {
        original_rlimit = original;
        const new: std.posix.rlimit = .{
            .cur = @min(4096, original.max),
            .max = original.max,
        };
        if (std.posix.setrlimit(.NOFILE, new)) {
            std.log.debug("raised file descriptor limit of the Conpositor process to {d}", .{new.cur});
        } else |_| {
            std.log.err("setrlimit failed, using system default file descriptor limit of {d}", .{
                original.cur,
            });
        }
    } else |_| {
        std.log.err("getrlimit failed, using system default file descriptor limit ", .{});
    }

    self.home_path = try known_folders.getPath(self.io, allocator, self.environ_map, .home) orelse
        "";
    const libs_dir = self.environ_map.get("CONPOSITOR_LIB_DIR") orelse
        "/usr/share/conpositor";
    const config_dir = if (self.environ_map.get("CONPOSITOR_CONFIG_DIR")) |tmp|
        try allocator.dupe(u8, tmp)
    else
        try known_folders.getPath(self.io, allocator, self.environ_map, .local_configuration) orelse "";
    defer allocator.free(config_dir);

    const path: []const u8 = try std.fmt.allocPrint(allocator, "?;?.lua;" ++ // cwd
        "{s}/conpositor/?;{s}/conpositor/?.lua;" ++ // user config (config folder)
        "{s}/.conpositor/?;{s}/.conpositor/?.lua;" ++ // user config (home folder)
        "{s}/?;{s}/?.lua;" ++ // system libs
        "{s}/config/?;{s}/config/?.lua;" ++ // system config
        "/usr/lib/lua/?;/usr/lib/lua/?.lua" // lua libraries
    , .{
        config_dir, config_dir, // config folder
        self.home_path, self.home_path, // home folder
        libs_dir, libs_dir, // system libs
        libs_dir, libs_dir, // system config
        // lua libs
    });
    defer allocator.free(path);

    std.log.info("LUA_PATH: {s}", .{path});

    try self.lua.init(path);

    std.log.info("Init lua", .{});
}

pub fn applyRules(self: *Config, client: *Client) !void {
    return self.lua.applyRules(client);
}

pub fn mouseBind(self: *Config, bind: LuaSession.MouseBindData, pos: LuaVector, client: ?*Client) !bool {
    return self.lua.mouseBind(bind, pos, client);
}

pub fn keyBind(self: *Config, bind: LuaSession.BindData) !bool {
    return self.lua.keyBind(bind);
}

pub fn getFont(self: *Config) LuaSession.FontInfo {
    return self.lua.session.font;
}

pub fn getColor(self: *Config, active: bool, palette: LuaSession.PaletteColor) *const [4]f32 {
    if (active)
        return self.lua.session.active_colors.getPtrConst(palette)
    else
        return self.lua.session.inactive_colors.getPtrConst(palette);
}

pub fn getLayouts(self: *Config) []*Layout {
    return self.layouts.items;
}

// TODO: should be stored here
pub fn getTags(self: *Config) [][:0]const u8 {
    return self.lua.session.tags.items;
}

// TODO: should be stored here
pub fn getTitlePad(self: *Config) i32 {
    return self.lua.session.title_pad;
}

// TODO: should be stored here
pub fn getTitleHeight(self: *Config) i32 {
    return self.lua.session.font.size + 2 * self.lua.session.title_pad;
}

pub fn sourcePath(self: *Config, path: []const u8) Error!void {
    const home_dir = self.home_path;

    const file = try std.fmt.allocPrintSentinel(allocator, "{s}/.config/conpositor/{s}", .{
        home_dir,
        path,
    }, 0);
    defer allocator.free(file);

    std.log.info("Source lua {s}", .{file});

    return self.lua.runFile(file);
}

// runs a command
// TODO: Should this be moved outside of here?
pub fn run(self: *Config, command: []const u8) !LuaContext.RunResult {
    return self.lua.run(command);
}

pub fn sendEvent(self: *Config, comptime T: type, event_id: LuaSession.Event, data: T) Error!bool {
    return self.lua.sendEvent(T, event_id, data);
}

// TODO: Should debug utils like this be broken out somewhere
pub fn conpositorLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@import("builtin").is_test)
        return;

    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);

    var buffer: [64]u8 = undefined;
    const stderr = std.debug.lockStderr(&buffer).terminal();
    defer std.debug.unlockStderr();

    const scope_prefix = "(" ++ switch (scope) {
        std.log.default_log_scope => "Conpositor",
        else => @tagName(scope),
    } ++ "): ";

    const prefix = "[" ++ switch (comptime level) {
        .err => "Err",
        .warn => "Wrn",
        .info => "Inf",
        .debug => "Dbg",
    } ++ "] " ++ scope_prefix;

    const color = switch (level) {
        .err => "\x1b[1;91m",
        .warn => "\x1b[1;33m",
        .info => "\x1b[1;37m",
        .debug => "\x1b[0;37m",
    };

    // Print the message to stderr, silently ignoring any errors
    nosuspend stderr.writer.print(prefix ++ color ++ format ++ "\x1b[m\n", args) catch return;
}

pub fn deinit(self: *Config) void {
    cleanupChild();
    self.lua.deinit();

    allocator.free(self.home_path);
}

// Signal that an object was freed
pub fn destroy(self: *Config, kind: [:0]const u8, base: anytype) void {
    self.lua.destroy(kind, base);
}
