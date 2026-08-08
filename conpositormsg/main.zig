const std = @import("std");
const wl = @import("wayland").client.wl;
const conpositor = @import("wayland").client.conpositor;

// Inspired by https://github.com/riverwm/river/blob/master/riverctl/main.zig

var gpa: std.heap.DebugAllocator(.{}) = .{};
const allocator = gpa.allocator();

pub const Globals = struct {
    manager: ?*conpositor.LuaManagerV1 = null,
    runner: ?*conpositor.LuaRunnerV1 = null,
    seat: ?*wl.Seat = null,
    command: [:0]const u8 = "",
    stdout: std.Io.File.Writer,
    stderr: std.Io.File.Writer,

    pub fn deinit(self: *Globals) void {
        if (self.runner) |runner|
            runner.destroy();
        allocator.free(self.command);
        self.stdout.flush() catch unreachable;
        self.stderr.flush() catch unreachable;
    }
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var idx: usize = 1;
    if (args.len <= 1)
        return error.MissingParams;

    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    const stdout: std.Io.File = .stdout();
    const stderr: std.Io.File = .stderr();

    var globals = Globals{
        .stdout = stdout.writer(init.io, &.{}),
        .stderr = stderr.writer(init.io, &.{}),
    };
    errdefer globals.deinit();

    registry.setListener(*Globals, registryListener, &globals);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    const manager = globals.manager orelse return error.ConpositorLuaManagerNotAdvertised;

    var run_command: std.array_list.Managed(u8) = .init(allocator);
    defer run_command.deinit();

    var first: bool = true;
    while (idx < args.len) : (idx += 1) {
        if (!first)
            try run_command.appendSlice(" ");

        try run_command.appendSlice(args[idx]);
        first = false;
    }
    globals.command = try allocator.dupeZ(u8, std.mem.trim(u8, run_command.items, " "));
    std.log.info("Running {s}", .{globals.command});

    const handle = try manager.createRunner();
    handle.setListener(*Globals, runnerListener, &globals);

    handle.begin(globals.command);

    while (true)
        switch (display.dispatch()) {
            .SUCCESS => {},
            else => |err| {
                std.log.err("Failed to send command {s}", .{@tagName(err)});
                return error.FailedToSend;
            },
        };
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, globals: *Globals) void {
    switch (event) {
        .global => |global| {
            if (std.mem.orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                std.debug.assert(globals.seat == null); // TODO: support multiple seats
                globals.seat = registry.bind(global.name, wl.Seat, 1) catch @panic("out of memory");
            } else if (std.mem.orderZ(u8, global.interface, conpositor.LuaManagerV1.interface.name) == .eq) {
                globals.manager = registry.bind(global.name, conpositor.LuaManagerV1, 1) catch @panic("out of memory");
            }
        },
        .global_remove => {},
    }
}

fn runnerListener(_: *conpositor.LuaRunnerV1, event: conpositor.LuaRunnerV1.Event, globals: *Globals) void {
    switch (event) {
        .print => |req| {
            globals.stderr.interface.print("{s}\n", .{req.message}) catch {};
        },
        .success => {
            globals.deinit();

            std.c.exit(0);
        },
        .@"return" => |req| {
            globals.stdout.interface.print("{s}\n", .{req.value}) catch {};

            globals.deinit();
            std.c.exit(0);
        },
        .fail => |req| {
            globals.stderr.interface.print("\x1b[31m{s}\x1b[0m\n", .{req.message}) catch {};

            globals.deinit();
            std.c.exit(1);
        },
    }
}
