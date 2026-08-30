// The monitor object is primarily an abstraction over wayland outputs,
// it also maintains storing what portion of layouts is dirty.
//
// NOTES:
const conpositor = @import("wayland").server.conpositor;
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const std = @import("std");

const IpcManager = @import("IpcManager.zig");
const LayerSurface = @import("LayerSurface.zig");
const Config = @import("Config.zig");
const Session = @import("Session.zig");
const Client = @import("Client.zig");
const Layout = @import("Layout.zig");

const trace = @import("trace.zig");

const Monitor = @This();

const allocator = Config.allocator;

const TOTAL_LAYERS = 4;

// Layers that render above clients
const LAYERS_ABOVE_SHELL = [_]u32{ 3, 2 };

// A ref to the parent session, useful for quick access
session: *Session,

// The next monitor
link: wl.list.Link = undefined,

// The associated object
output: *wlr.Output,
scene_output: *wlr.SceneOutput,

// Used to clear the background when a window is fullscreen, but doesnt fill
fullscreen_bg: *wlr.SceneRect,

// The resolution and position of the monitor
mode: wlr.Box,

// the working bounds of the monitor
window: wlr.Box,

// Layer surface lists
layers: [TOTAL_LAYERS]wl.list.Head(LayerSurface, .link) = undefined,

// What tag is active on the monitor
tag: u8 = 0,

// The monitors active layout.
layout: ?*Layout = null,

// Gaps values
// inner gaps are window-window boundries
// outer gaps are window-margin boundries
gaps_inner: i32 = 0,
gaps_outer: i32 = 0,

// TODO: Is this really optimal?
// used to calculate if the monitor is now dirty
last_usage: [256]bool = .{false} ** 256,

// TODO: Is this nessesary
last_frame: std.posix.timespec = .{ .sec = 0, .nsec = 0 },

dirty: packed struct {
    layout: bool = false,
    force_layout: bool = false,
    tabs: bool = false,
    focus: bool = false,
} = .{},

deinit_event: trace.Event(*wlr.Output, "deinit", Monitor) = .{},
frame_event: trace.Event(*wlr.Output, "frame", Monitor) = .{},
present_event: trace.Event(*wlr.Output.event.Present, "present", Monitor) = .{},

pub fn init(session: *Session, output: *wlr.Output) !void {
    if (!output.initRender(session.wlr_allocator, session.renderer))
        return error.DisplayRenderInitFailed;

    const fullscreen_bg = try session.layers.get(.LyrFS).createSceneRect(0, 0, session.config.getColor(false, .background));
    fullscreen_bg.node.setEnabled(false);

    var state = wlr.Output.State.init();
    defer state.finish();

    state.setEnabled(true);
    state.setScale(1.0);
    state.setTransform(.normal);
    state.setAdaptiveSyncEnabled(true);

    if (output.preferredMode()) |pref_mode| {
        state.setMode(pref_mode);
    }

    if (!output.commitState(&state)) {
        std.log.err("Initial output commit with preferred mode failed, trying all modes", .{});

        var iter = output.modes.iterator(.forward);
        while (iter.next()) |mode| {
            state.setMode(mode);
            if (output.commitState(&state)) {
                std.log.info("Initial output commit succeeded with mode {}x{}@{}mHz", .{
                    mode.width,
                    mode.height,
                    mode.refresh,
                });
                break;
            } else {
                std.log.err("Initial output commit failed with mode {}x{}@{}mHz", .{
                    mode.width,
                    mode.height,
                    mode.refresh,
                });
            }
        }
    }

    const scene_output = try session.scene.createSceneOutput(output);

    const result: *Monitor = try allocator.create(Monitor);
    output.data = @ptrCast(@alignCast(result));

    std.log.debug("Created monitor {*} for {s}", .{ result, output.name });

    session.monitors.append(result);

    result.* = .{
        .session = session,
        .output = output,
        .fullscreen_bg = fullscreen_bg,
        .scene_output = scene_output,
        .mode = std.mem.zeroes(wlr.Box),
        .window = std.mem.zeroes(wlr.Box),
    };

    for (&result.layers) |*layer|
        layer.init();

    output.events.frame.add(&result.frame_event.event);
    output.events.present.add(&result.present_event.event);
    output.events.destroy.add(&result.deinit_event.event);

    const layout_output = try session.output_layout.add(result.output, result.mode.x, result.mode.y);

    std.log.debug("Output layout is {}", .{layout_output});

    result.scene_output.setPosition(layout_output.x, layout_output.y);

    try session.updateMons();

    // Tell lua that a monitor was created.
    _ = try session.config.sendEvent(@import("LuaTypes/Monitor.zig"), .add_monitor, .{ .child = result });
}

pub fn close(self: *Monitor) !void {
    var miter = self.session.monitors.iterator(.forward);
    while (miter.next()) |monitor| {
        if (!monitor.output.enabled or monitor == self)
            continue;

        try self.session.focusMonitor(monitor);
        break;
    }
    const new_mon = self.session.focusedMonitor orelse return;

    var citer = self.session.clients.iterator(.forward);
    while (citer.next()) |client| {
        if (client.monitor == self) {
            client.setFloatingSize(.{
                .x = client.floating_bounds.x - self.mode.x + new_mon.mode.x,
                .y = client.floating_bounds.y - self.mode.y + new_mon.mode.y,
                .width = client.floating_bounds.width,
                .height = client.floating_bounds.height,
            });

            try client.setMonitor(new_mon);
        }
    }
    if (new_mon.getFocusedClient()) |focus|
        try self.session.focusClient(focus, true)
    else
        self.session.focusClear();
}

pub fn isClientVisible(self: *Monitor, client: *Client) bool {
    return client.floating or
        (if (self.layout) |layout| layout.container.has(client.container) else true) and
            client.monitor == self and self.tag == client.tag;
}

pub fn getFocusedClient(self: *Monitor) ?*Client {
    {
        var iter = self.session.focus_clients.iterator(.forward);
        while (iter.next()) |client| {
            if (self.isClientVisible(client) and client.fullscreen)
                return client;
        }
    }

    var iter = self.session.focus_clients.iterator(.forward);

    if (self.session.input.seat.keyboard_state.focused_surface == null)
        return null;

    return focused: while (iter.next()) |client| {
        if (self.isClientVisible(client))
            break :focused client;
    } else null;
}

pub fn setActiveTag(self: *Monitor, tag: u8) void {
    if (self.tag == tag)
        return;

    self.tag = tag;
    self.dirty.layout = true;
    self.dirty.tabs = true;
    self.dirty.focus = true;
}

pub fn arrangeLayers(self: *Monitor) !void {
    var usable = self.mode;

    if (!self.output.enabled) return;

    for (0..TOTAL_LAYERS) |i|
        self.arrangeLayer(TOTAL_LAYERS - 1 - i, &usable, true);

    if (!std.meta.eql(usable, self.window)) {
        self.window = usable;
        self.dirty.layout = true;
    }
}

pub fn arrangeLayersAbove(self: *Monitor) !void {
    var usable = self.window;

    for (0..TOTAL_LAYERS) |i|
        self.arrangeLayer(TOTAL_LAYERS - 1 - i, &usable, false);

    for (LAYERS_ABOVE_SHELL) |idx| {
        var iter = self.layers[idx].iterator(.reverse);
        while (iter.next()) |layersurface| {
            if (!self.session.input.locked and
                layersurface.surface.current.keyboard_interactive == .none and
                layersurface.mapped)
            {
                self.session.focusClear();
                self.session.exclusive_focus = layersurface.surface.surface;
                layersurface.notifyEnter(self.session.input.seat, self.session.input.seat.getKeyboard());
                return;
            }
        }
    }
}

pub fn setGaps(self: *Monitor, pos: enum { inner, outer }, gaps: i32) void {
    const ptr = switch (pos) {
        .inner => &self.gaps_inner,
        .outer => &self.gaps_outer,
    };

    if (ptr.* == gaps)
        return;

    ptr.* = gaps;
    self.dirty.force_layout = true;
}

pub fn setLayout(self: *Monitor, layout: ?*Layout) void {
    if (self.layout == layout)
        return;

    if (self.session.config.lua.session.layouts.items.len == 0)
        return;

    self.layout = layout;
    self.dirty.force_layout = true;
}

pub fn deinit(self: *Monitor, _: *wlr.Output) !void {
    self.present_event.event.link.remove();
    self.frame_event.event.link.remove();
    self.deinit_event.event.link.remove();

    self.link.remove();

    allocator.destroy(self);
}

pub fn frame(self: *Monitor, _: *wlr.Output) !void {
    // TODO:Figure out why this skips

    // const tmp_now: std.posix.timespec = std.posix.clock_gettime(std.posix.CLOCK.MONOTONIC) catch
    //     @panic("CLOCK_MONOTONIC not supported");
    // commit: {
    //     // give a layout 300ns to apply
    //     if (tmp_now.nsec - self.last_frame.nsec < 300_000) {
    //         var iter = self.session.clients.iterator(.forward);
    //         while (iter.next()) |client| {
    //             if (client.resize_serial != null and
    //                 client.surface == .XDG and
    //                 client.monitor == self and
    //                 self.clientVisible(client) and
    //                 !client.isStopped())
    //                 break :commit;
    //         }
    //     } else {
    //         var iter = self.session.clients.iterator(.forward);
    //         while (iter.next()) |client| {
    //             client.resize_serial = null;
    //         }
    //     }

    //     _ = self.scene_output.commit(null);
    //     self.last_frame = tmp_now;
    // }
    commit: {
        var iter = self.session.clients.iterator(.forward);
        while (iter.next()) |client| {
            if (client.resize != 0 and
                client.monitor == self and
                client.visible and
                !client.isStopped())
                break :commit;
        }

        _ = self.scene_output.commit(null);
    }

    var now: std.posix.timespec = undefined;
    if (std.c.clock_gettime(std.posix.CLOCK.MONOTONIC, &now) > 0)
        @panic("CLOCK_MONOTONIC not supported");
    self.scene_output.sendFrameDone(&now);

    var pending: wlr.Output.State = std.mem.zeroInit(wlr.Output.State, .{});
    pending.finish();
}

pub fn present(self: *Monitor, _: *wlr.Output.event.Present) !void {
    if (self.dirty.layout or self.dirty.force_layout)
        try self.updateLayout();

    if (self.dirty.tabs)
        try self.updateTabs();

    if (self.dirty.focus) {
        try self.session.input.motionNotify(0);
        self.dirty.focus = false;
    }

    var iter = self.session.clients.iterator(.forward);
    while (iter.next()) |client| {
        if (client.monitor == self)
            try client.update();
    }
}

fn updateTabs(self: *Monitor) !void {
    defer self.dirty.tabs = false;

    std.log.debug("Update monitor tabs {*}", .{self});

    var iter = self.session.focus_clients.iterator(.forward);
    while (iter.next()) |client| {
        const visible = self.isClientVisible(client);
        if (client.monitor == self and !client.floating and visible) {
            client.dirty.title = true;
        }
    }
}

pub fn updateLayout(self: *Monitor) !void {
    defer self.dirty.layout = false;
    defer self.dirty.force_layout = false;

    std.log.debug("Update monitor layout {*}", .{self});

    // TODO: dynamic/packed allocation?
    var usage: [256]bool = .{false} ** 256;

    {
        var iter = self.session.focus_clients.iterator(.forward);
        while (iter.next()) |client| {
            if (client.monitor == self) {
                const visible = self.isClientVisible(client);
                client.setVisible(visible);

                if (!client.floating and visible) {
                    client.hide_frame = usage[client.container];
                    usage[client.container] = true;
                } else {
                    client.hide_frame = false;
                }
            }
        }
    }

    const resize = if (self.layout) |layout|
        layout.calcDirty(&self.last_usage, &usage)
    else
        false;

    @memcpy(&self.last_usage, &usage);

    var iter = self.session.focus_clients.iterator(.forward);
    while (iter.next()) |client| {
        if (client.monitor == self) {
            const visible = self.isClientVisible(client);

            if (visible) {
                const new_size = if (self.layout) |layout|
                    layout.getSize(
                        client.container,
                        self.window,
                        &usage,
                        self.gaps_inner,
                        self.gaps_outer,
                    )
                else
                    wlr.Box{
                        .x = self.window.x + self.gaps_outer + self.gaps_inner,
                        .y = self.window.y + self.gaps_outer + self.gaps_inner,
                        .width = self.window.width - 2 * (self.gaps_outer + self.gaps_inner),
                        .height = self.window.height - 2 * (self.gaps_outer + self.gaps_inner),
                    };

                client.setContainerTitle(new_size.y != self.window.y);

                if (resize or client.dirty.container or self.dirty.force_layout)
                    client.setContainerSize(new_size);

                client.dirty.container = false;
            }
        }
    }

    // TODO: update fullscreen state

    try self.session.input.motionNotify(0);
    try self.arrangeLayersAbove();
}

fn arrangeLayer(self: *Monitor, idx: usize, usable: *wlr.Box, exclusive: bool) void {
    const full_area = self.mode;

    var iter = self.layers[idx].iterator(.forward);
    while (iter.next()) |layersurface| {
        const wlr_layer_surface = layersurface.surface;

        const state = &wlr_layer_surface.current;

        if (!wlr_layer_surface.initialized) continue;

        if (exclusive != (state.exclusive_zone > 0))
            continue;

        layersurface.scene.configure(&full_area, usable);
        layersurface.popups.node.setPosition(
            layersurface.scene_tree.node.x,
            layersurface.scene_tree.node.y,
        );
        layersurface.bounds.x = layersurface.scene_tree.node.x;
        layersurface.bounds.y = layersurface.scene_tree.node.y;
    }
}
