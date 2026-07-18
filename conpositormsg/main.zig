const std = @import("std");
const wl = @import("wayland").client.wl;
const conpositor = @import("wayland").client.conpositor;

// Inspired by https://github.com/riverwm/river/blob/master/riverctl/main.zig

var gpa: std.heap.DebugAllocator(.{}) = .{};
const allocator = gpa.allocator();

pub const Globals = struct {
    manager: ?*conpositor.IpcManagerV1 = null,
    seat: ?*wl.Seat = null,
};

var command: []const u8 = "";

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var idx: usize = 1;
    if (args.len <= 1)
        return error.MissingParams;

    command = args[idx];
    idx += 1;

    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    var globals = Globals{};

    registry.setListener(*Globals, registryListener, &globals);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    const manager = globals.manager orelse return error.ConpositorIpcManagerNotAdvertised;
    const session = try manager.getSession();

    if (std.mem.eql(u8, command, "run")) {
        var run_command: std.array_list.Managed(u8) = .init(allocator);
        defer run_command.deinit();

        var first: bool = true;
        while (idx < args.len) : (idx += 1) {
            if (first) {
                try run_command.appendSlice(" ");
                first = false;
            }
            try run_command.appendSlice(args[idx]);
        }
        const new_command = try allocator.dupeZ(u8, std.mem.trim(u8, run_command.items, " "));

        const handle = try session.runCommand(new_command);
        handle.setListener(?*anyopaque, commandListener, null);
    } else {
        const output = try session.getFocusedOutput();
        output.setListener(?*anyopaque, outputListener, null);
    }

    while (true) {
        if (display.dispatch() != .SUCCESS) return error.FailedToSend;
    }
}

var statusData: struct {
    focus: ?struct {
        label: [*:0]const u8,
        appid: [*:0]const u8,
        icon: [*:0]const u8,
        title: [*:0]const u8,
    } = null,
    tags: [][*:0]const u8 = &.{},
    layout: ?[*:0]const u8 = null,
    activeTag: [*:0]const u8 = "",
    changed: packed struct {
        focus: bool = false,
        tags: bool = false,
        layout: bool = false,
        activeTag: bool = false,
    } = .{},
} = .{};

fn writeOutput() !void {
    const debug_io = std.Options.debug_io;

    const stdout: std.Io.File = .stdout();
    var writer = stdout.writer(debug_io, &.{});

    defer statusData.changed = .{};

    if (std.mem.eql(u8, command, "status")) {
        if (statusData.focus) |focus| {
            try writer.interface.print("focused:\n", .{});
            try writer.interface.print("  label: {s}\n", .{focus.label});
            try writer.interface.print("  appid: {s}\n", .{focus.appid});
            try writer.interface.print("  icon:  {s}\n", .{focus.icon});
            try writer.interface.print("  title: {s}\n", .{focus.title});
        }

        try writer.interface.print("tags:\n", .{});
        try writer.interface.print("  count: {}\n", .{statusData.tags.len});
        try writer.interface.print("  active: {s}\n", .{statusData.activeTag});
        for (statusData.tags, 0..) |tag_name, idx| {
            try writer.interface.print("  names[{}]: {s}\n", .{ idx, tag_name });
        }

        if (statusData.layout) |layout|
            try writer.interface.print("layout: {s}\n", .{layout});
    } else if (std.mem.eql(u8, command, "layout")) {
        if (!statusData.changed.layout)
            return;

        if (statusData.layout) |layout|
            try writer.interface.print("{s}\n", .{layout});
    } else if (std.mem.eql(u8, command, "icon")) {
        if (!statusData.changed.focus)
            return;

        if (statusData.focus) |focus| {
            try writer.interface.print("{s}\n", .{focus.icon});
        } else {
            try writer.interface.print("\n", .{});
        }
    } else if (std.mem.eql(u8, command, "label")) {
        if (!statusData.changed.focus)
            return;

        if (statusData.focus) |focus| {
            try writer.interface.print("{s}\n", .{focus.label});
        } else {
            try writer.interface.print("Desktop\n", .{});
        }
    } else if (std.mem.eql(u8, command, "tag")) {
        if (!statusData.changed.tags and !statusData.changed.activeTag)
            return;

        try writer.interface.print("{s}\n", .{statusData.activeTag});
    } else {
        const stderr: std.Io.File = .stdout();
        var err_writer = stderr.writer(debug_io, &.{});

        try err_writer.interface.print("missing command\n", .{});
    }
}

fn outputListener(_: *conpositor.IpcOutputV1, event: conpositor.IpcOutputV1.Event, _: ?*anyopaque) void {
    switch (event) {
        .frame => {
            writeOutput() catch @panic("stdout write failed");

            std.c.exit(0);
        },
        .tags => |tags| {
            statusData.tags = allocator.alloc([*:0]const u8, tags.amount) catch &.{};

            statusData.changed.tags = true;
        },
        .toggle_visibility => {},
        .active => {},
        .tag => |tag| {
            statusData.tags[@intCast(tag.tag)] = tag.name;
            if (tag.state == .active) {
                statusData.activeTag = tag.name;

                statusData.changed.activeTag = true;
            }

            statusData.changed.tags = true;
        },
        .layout => |layout| {
            statusData.layout = layout.name;

            statusData.changed.layout = true;
        },
        .clear_focus => {
            statusData.focus = null;

            statusData.changed.focus = true;
        },
        .focus => |focus| {
            statusData.focus = .{
                .label = focus.label,
                .appid = focus.appid,
                .icon = focus.icon,
                .title = focus.title,
            };

            statusData.changed.focus = true;
        },
    }
}

fn commandListener(_: *conpositor.CommandOutputV1, event: conpositor.CommandOutputV1.Event, _: ?*anyopaque) void {
    switch (event) {
        .success => |req| {
            const debug_io = std.Options.debug_io;

            const stdout: std.Io.File = .stdout();
            var writer = stdout.writer(debug_io, &.{});

            writer.interface.print("{s}\n", .{req.output}) catch {};

            std.c.exit(0);
        },
        .fail => |req| {
            const debug_io = std.Options.debug_io;

            const stdout: std.Io.File = .stdout();
            var writer = stdout.writer(debug_io, &.{});

            writer.interface.print("Failed: {s}\n", .{req.reason}) catch {};

            std.c.exit(1);
        },
    }
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, globals: *Globals) void {
    switch (event) {
        .global => |global| {
            if (std.mem.orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                std.debug.assert(globals.seat == null); // TODO: support multiple seats
                globals.seat = registry.bind(global.name, wl.Seat, 1) catch @panic("out of memory");
            } else if (std.mem.orderZ(u8, global.interface, conpositor.IpcManagerV1.interface.name) == .eq) {
                globals.manager = registry.bind(global.name, conpositor.IpcManagerV1, 1) catch @panic("out of memory");
            }
        },
        .global_remove => {},
    }
}
