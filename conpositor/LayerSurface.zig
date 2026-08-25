const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const std = @import("std");

const trace = @import("trace.zig");
const Session = @import("Session.zig");
const Monitor = @import("Monitor.zig");
const Config = @import("Config.zig");

const LayerSurface = @This();

const allocator = Config.allocator;

surface_id: u8 = 25,

session: *Session,
monitor: ?*Monitor,
surface: *wlr.LayerSurfaceV1,
scene: *wlr.SceneLayerSurfaceV1,
scene_tree: *wlr.SceneTree,
popups: *wlr.SceneTree,
mapped: bool = false,
link: wl.list.Link = undefined,
bounds: wlr.Box = std.mem.zeroes(wlr.Box),

map_event: trace.Event(void, "map", LayerSurface) = .{},
unmap_event: trace.Event(void, "unmap", LayerSurface) = .{},
commit_event: trace.Event(*wlr.Surface, "commit", LayerSurface) = .{},
deinit_event: trace.Event(*wlr.Surface, "deinit", LayerSurface) = .{},

pub fn init(session: *Session, surf: *wlr.LayerSurfaceV1) !void {
    const monitor: *Monitor = if (surf.output) |output|
        @as(*Monitor, @ptrCast(@alignCast(output.data)))
    else
        session.focusedMonitor orelse {
            std.log.debug("Failed to init surf {*}, no focused monitor", .{surf});

            surf.destroy();
            return;
        };

    const parent_scene = session.layers.get(@enumFromInt(@intFromEnum(surf.pending.layer)));
    const popups = try parent_scene.createSceneTree();
    const scene = try parent_scene.createSceneLayerSurfaceV1(surf);
    const scene_tree = scene.tree;

    surf.output = monitor.output;

    const result = try allocator.create(LayerSurface);
    scene_tree.node.data = @ptrCast(@alignCast(result));
    surf.data = @ptrCast(@alignCast(result));

    result.* = .{
        .surface = surf,
        .session = session,
        .monitor = monitor,
        .scene = scene,
        .scene_tree = scene_tree,
        .popups = popups,
    };

    surf.surface.events.map.add(&result.map_event.event);
    surf.surface.events.unmap.add(&result.unmap_event.event);
    surf.surface.events.commit.add(&result.commit_event.event);
    surf.surface.events.destroy.add(&result.deinit_event.event);

    monitor.layers[@intCast(@intFromEnum(surf.pending.layer))].append(result);

    const old_state = surf.current;
    surf.current = surf.pending;
    try monitor.arrangeLayers();
    surf.current = old_state;

    std.log.debug("Tracking layersurface {*} with {*}", .{ surf, result });
}

pub fn notifyEnter(self: *LayerSurface, seat: *wlr.Seat, kb: ?*wlr.Keyboard) void {
    if (kb) |keyb| {
        seat.keyboardNotifyEnter(self.surface.surface, &keyb.keycodes, &keyb.modifiers);
    } else {
        seat.keyboardNotifyEnter(self.surface.surface, &.{}, null);
    }
}

pub fn map(self: *LayerSurface) !void {
    try self.session.input.motionNotify(0);

    std.log.debug("Maped layer surface {*}", .{self});
}

pub fn commit(self: *LayerSurface, _: *wlr.Surface) !void {
    std.log.debug("Configure layer surface {*} on {*}", .{ self, self.monitor });

    if (self.surface.output) |output| {
        self.monitor = @ptrCast(@alignCast(output.data));
    } else return;

    if (self.monitor == null)
        return;

    const lyr = self.session.layers.get(@enumFromInt(@intFromEnum(self.surface.current.layer)));
    if (lyr != self.scene_tree.node.parent) {
        self.scene_tree.node.reparent(lyr);
        self.popups.node.reparent(lyr);
        self.link.remove();
        self.monitor.?.layers[@intCast(@intFromEnum(self.surface.current.layer))].append(self);
    }

    if (@intFromEnum(self.surface.current.layer) < 2)
        self.popups.node.reparent(self.session.layers.get(.LyrTop));

    if (@as(u32, @bitCast(self.surface.current.committed)) == 0 and self.mapped == self.surface.surface.mapped)
        return;

    self.mapped = self.surface.surface.mapped;

    if (self.monitor) |m|
        try m.arrangeLayers();
}

pub fn unmap(self: *LayerSurface) !void {
    self.mapped = false;
    self.scene_tree.node.setEnabled(false);

    if (self.session.exclusive_focus == self.surface.surface)
        self.session.exclusive_focus = null;

    self.monitor = @ptrCast(@alignCast(self.surface.output.?.data));
    if (self.monitor) |m|
        try m.arrangeLayers();

    try self.session.input.motionNotify(0);

    std.log.debug("Unmapped layer surface {*}", .{self});
}

pub fn deinit(self: *LayerSurface, _: *wlr.Surface) !void {
    std.log.debug("Deinit layer surface {*}", .{self});

    self.link.remove();

    if (self.monitor) |m|
        m.arrangeLayers() catch {};

    self.map_event.event.link.remove();
    self.unmap_event.event.link.remove();
    self.deinit_event.event.link.remove();
    self.commit_event.event.link.remove();

    allocator.destroy(self);
}
