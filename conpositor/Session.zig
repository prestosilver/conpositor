const wl = @import("wayland").server.wl;
const conpositor = @import("wayland").server.conpositor;
const wlr = @import("wlroots");
const std = @import("std");
const xcb = @import("xcb");

const c = @import("c.zig").c;

const trace = @import("trace.zig");
const Config = @import("Config.zig");
const Monitor = @import("Monitor.zig");
const Client = @import("Client.zig");
const Input = @import("Input.zig");
const LayerSurface = @import("LayerSurface.zig");
const IpcManager = @import("IpcManager.zig");
const ObjectTag = @import("ObjectTag.zig").ObjectTag;

const Session = @This();

const allocator = Config.allocator;

pub const Layer = enum {
    LyrBg,
    LyrBottom,
    LyrTop,
    LyrOverlay,

    LyrTileShadows,
    LyrTile,
    LyrFloatShadows,
    LyrFloat,
    LyrFS,
    LyrDragIcon,
    LyrBlock,
};

const CycleDir = enum { forward, backward };
const NetAtom = enum { window_type_dialog, window_type_splash, window_type_toolbar, window_type_utility };

pub const Error = error{
    ServerCreateFailed,
    BackendCreateFailed,
    RendererCreateFailed,
    AllocatorCreateFailed,
    XwaylandCreateFailed,
    GlobalCreateFailed,
    RenderInitFailed,
    BackendStartFailed,
    AddSocketFailed,
    SessionNotSetup,
    OutOfMemory,
    Unexpected,
} || Config.Error;

config: Config,

server: *wl.Server,
backend: *wlr.Backend,
scene: *wlr.Scene,
renderer: *wlr.Renderer,
wlr_allocator: *wlr.Allocator,
output_layout: *wlr.OutputLayout,
output_manager: *wlr.OutputManagerV1,
layers: std.EnumArray(Layer, *wlr.SceneTree),
xdg_activation: *wlr.XdgActivationV1,

idle_notifier: *wlr.IdleNotifierV1,
idle_inhibit_manager: *wlr.IdleInhibitManagerV1,
layer_shell: *wlr.LayerShellV1,
xdg_shell: *wlr.XdgShell,
session_lock_manager: *wlr.SessionLockManagerV1,

xdg_decoration_manager: *wlr.XdgDecorationManagerV1,
compositor: *wlr.Compositor,
xwayland: ?*wlr.Xwayland,
net_atoms: std.EnumArray(NetAtom, c.xcb_atom_t),

io: std.Io,
environ_map: *std.process.Environ.Map,

input: Input = undefined,

monitors: wl.list.Head(Monitor, .link) = undefined,
clients: wl.list.Head(Client, .link) = undefined,
focus_clients: wl.list.Head(Client, .focus_link) = undefined,
exclusive_focus: ?*wlr.Surface = null,

focusedMonitor: ?*Monitor = null,

outputlayout_event: trace.Event(*wlr.OutputLayout, "outputlayout", Session) = .{},
newoutput_event: trace.Event(*wlr.Output, "newoutput", Session) = .{},

outputmanagerapply_event: trace.Event(*wlr.OutputConfigurationV1, "outputmanagerapply", Session) = .{},
outputmanagertest_event: trace.Event(*wlr.OutputConfigurationV1, "outputmanagertest", Session) = .{},

xwaylandready_event: trace.Event(void, "xwaylandready", Session) = .{},
commitpopup_event: trace.Event(*wlr.Surface, "commitpopup", Session) = .{},

newlayersurface_event: trace.Event(*wlr.LayerSurfaceV1, "newlayersurface", Session) = .{},
newxdgtoplevel_event: trace.Event(*wlr.XdgToplevel, "newxdgtoplevel", Session) = .{},
newxdgsurface_event: trace.Event(*wlr.XdgSurface, "newxdgsurface", Session) = .{},
newxdgpopup_event: trace.Event(*wlr.XdgPopup, "newxdgpopup", Session) = .{},
newxwaylandsurface_event: trace.Event(*wlr.XwaylandSurface, "newxwaylandsurface", Session) = .{},
newtopleveldecoration_event: trace.Event(*wlr.XdgToplevelDecorationV1, "newtopleveldecoration", Session) = .{},

events_attached: bool = false,

const STACKING_ORDER = [_]Layer{
    .LyrBg,
    .LyrBottom,

    .LyrTile,
    .LyrFloat,
    .LyrFS,
    .LyrDragIcon,
    .LyrBlock,

    .LyrTop,
    .LyrOverlay,
};

const FOCUS_ORDER = blk: {
    var tmp = STACKING_ORDER;
    std.mem.reverse(Layer, &tmp);
    break :blk tmp;
};

pub fn deinit(self: *Session) void {
    self.server.destroyClients();
    self.config.deinit();

    if (self.events_attached) {
        self.events_attached = false;

        self.outputlayout_event.event.link.remove();
        self.newoutput_event.event.link.remove();
        self.newxdgtoplevel_event.event.link.remove();
        self.newxdgsurface_event.event.link.remove();
        self.newxdgpopup_event.event.link.remove();
        self.newlayersurface_event.event.link.remove();
        self.newtopleveldecoration_event.event.link.remove();
        self.newxwaylandsurface_event.event.link.remove();
        self.xwaylandready_event.event.link.remove();
        self.outputmanagerapply_event.event.link.remove();
        self.outputmanagertest_event.event.link.remove();
    }

    self.input.deinit();

    self.xwayland.?.destroy();
    self.xwayland = null;

    self.backend.destroy();

    self.renderer.destroy();
    self.wlr_allocator.destroy();

    self.scene.tree.node.destroy();

    self.server.destroy();
}

pub fn newtopleveldecoration(self: *Session, _: *wlr.XdgToplevelDecorationV1) !void {
    _ = self;
}

pub fn outputmanagertest(self: *Session, output_configuration: *wlr.OutputConfigurationV1) !void {
    return self.applyOutputLayout(true, output_configuration);
}

pub fn outputmanagerapply(self: *Session, output_configuration: *wlr.OutputConfigurationV1) !void {
    return self.applyOutputLayout(false, output_configuration);
}

fn applyOutputLayout(self: *Session, is_test: bool, output_configuration: *wlr.OutputConfigurationV1) !void {
    std.log.debug("Monitor manager apply{s}", .{if (is_test) " dry" else ""});

    var ok = true;

    var iter = output_configuration.heads.iterator(.forward);
    while (iter.next()) |config_head| {
        const wlr_output = config_head.state.output;
        const monitor: *Monitor = @ptrCast(@alignCast(wlr_output.data));

        var state = wlr.Output.State.init();
        defer state.finish();

        state.setEnabled(config_head.state.enabled);

        if (config_head.state.enabled) {
            if (config_head.state.mode) |mode|
                state.setMode(mode)
            else
                state.setCustomMode(
                    config_head.state.custom_mode.width,
                    config_head.state.custom_mode.height,
                    config_head.state.custom_mode.refresh,
                );

            if (monitor.mode.x != config_head.state.x or
                monitor.mode.y != config_head.state.y)
            {
                const layout_output = try self.output_layout.add(monitor.output, config_head.state.x, config_head.state.y);
                monitor.scene_output.setPosition(layout_output.x, layout_output.y);
            }

            state.setTransform(config_head.state.transform);
            state.setScale(config_head.state.scale);
            state.setAdaptiveSyncEnabled(config_head.state.adaptive_sync_enabled);
        }

        ok = ok and
            if (is_test)
                wlr_output.testState(&state)
            else
                wlr_output.commitState(&state);

        std.log.debug("Move monitor {*} to {} {}", .{ monitor, monitor.mode, monitor.window });
    }

    if (ok) {
        output_configuration.sendSucceeded();
    } else {
        output_configuration.sendFailed();
    }

    output_configuration.destroy();

    try self.updateMons();
}

pub fn newoutput(self: *Session, output: *wlr.Output) !void {
    if (!output.initRender(self.wlr_allocator, self.renderer)) return;

    errdefer output.destroy();

    try Monitor.init(self, output);
    try self.updateMons();
}

pub fn newlayersurface(self: *Session, surface: *wlr.LayerSurfaceV1) !void {
    try LayerSurface.init(self, surface);
}

fn newPopup(self: *Session, popup: *wlr.XdgPopup) !void {
    popup.base.surface.events.commit.add(&self.commitpopup_event.event);
}

pub fn commitpopup(self: *Session, surface: *wlr.Surface) !void {
    // remove link
    defer self.commitpopup_event.event.link.remove();

    const popup_surface = wlr.XdgSurface.tryFromWlrSurface(surface) orelse return;
    const popup = popup_surface.role_data.popup orelse return;

    if (!popup.base.initial_commit)
        return;

    std.log.debug("Configure popup {*}", .{popup});

    const objects = self.getSurfaceObjects(popup.base.surface);
    if (popup.parent == null or objects.tag == null)
        return;

    const parent = @as(?*wlr.SceneTree, @ptrCast(@alignCast(popup.parent.?.data))) orelse
        if (objects.tag) |*tag| (if (tag.*.toClient()) |client|
            client.popup_surface
        else if (tag.*.toLayerSurface()) |layer_surface|
            layer_surface.scene_tree
        else
            unreachable) else unreachable;

    const new_surface = try parent.createSceneXdgSurface(popup.base);
    popup.base.surface.data = @ptrCast(@alignCast(new_surface));

    var box = if (objects.tag.?.* == .layer_surface)
        objects.monitor.?.mode
    else
        objects.monitor.?.window;

    const object_bounds = objects.tag.?.getBounds() orelse unreachable;
    box.x -= object_bounds.x;
    box.y -= object_bounds.y;

    popup.unconstrainFromBox(&box);
}

pub fn newxdgpopup(self: *Session, xdg_surface: *wlr.XdgPopup) !void {
    return self.newPopup(xdg_surface);
}

pub fn newxwaylandsurface(self: *Session, xwayland_surface: *wlr.XwaylandSurface) !void {
    return self.newClient(.{ .X11 = xwayland_surface });
}

pub fn newxdgtoplevel(self: *Session, xdg_surface: *wlr.XdgToplevel) !void {
    return self.newClient(.{ .XDG = xdg_surface.base });
}

pub fn newxdgsurface(self: *Session, xdg_surface: *wlr.XdgSurface) !void {
    return self.newClient(.{ .XDG = xdg_surface });
}

fn newClient(self: *Session, surface: Client.ClientSurface) !void {
    try Client.init(self, surface);
}

const logger = struct {
    fn readArg(vl: *std.builtin.VaList, comptime T: type) T {
        const T_size = @sizeOf(T);

        const is_float = switch (@typeInfo(T)) {
            .float => true,
            else => false,
        };

        if (is_float) {
            // Floating-point argument
            if (vl.fp_offset + 16 <= 128) {
                const reg_ptr = @as([*]u8, @ptrCast(vl.reg_save_area)) + vl.fp_offset;
                vl.fp_offset += 16;
                return @as(*const T, @ptrCast(@alignCast(reg_ptr))).*;
            } else {
                const ptr: *T = @ptrCast(@alignCast(vl.overflow_arg_area));
                vl.overflow_arg_area = @ptrFromInt(@intFromPtr(vl.overflow_arg_area) + T_size);
                return ptr.*;
            }
        } else {
            // Integer or pointer argument
            if (vl.gp_offset + 8 <= 48) {
                const reg_ptr = @as([*]u8, @ptrCast(vl.reg_save_area)) + vl.gp_offset;
                vl.gp_offset += 8;
                return @as(*const T, @ptrCast(@alignCast(reg_ptr))).*;
            } else {
                const ptr: *T = @ptrCast(@alignCast(vl.overflow_arg_area));
                vl.overflow_arg_area = @ptrFromInt(@intFromPtr(vl.overflow_arg_area) + T_size);
                return ptr.*;
            }
        }
    }

    pub fn log(importance: wlr.log.Importance, fmt: [*:0]const u8, args: *std.builtin.VaList) callconv(.c) void {
        var out = allocator.alloc(u8, std.mem.len(fmt) + 1024) catch unreachable;
        defer allocator.free(out);

        var out_idx: usize = 0;
        var in_idx: usize = 0;
        while (fmt[in_idx] != 0) {
            if (fmt[in_idx] == '%') {
                in_idx += 2;
                switch (fmt[(in_idx - 1)]) {
                    's' => out_idx += if (std.fmt.bufPrint(out[out_idx..], "{s}", get_arg: {
                        const arg = readArg(args, [*:0]const u8);
                        break :get_arg .{std.mem.span(arg)};
                    })) |val| val.len else |_| 0,
                    'u' => out_idx += if (std.fmt.bufPrint(out[out_idx..], "{}", get_arg: {
                        const arg = readArg(args, u64);
                        break :get_arg .{arg};
                    })) |val| val.len else |_| 0,
                    'd' => {
                        if (fmt[in_idx + 1] == 'X') {
                            out_idx += if (std.fmt.bufPrint(
                                out[out_idx..],
                                "{X}",
                                .{readArg(args, i64)},
                            )) |val| val.len else |_| 0;
                        } else {
                            out_idx += if (std.fmt.bufPrint(
                                out[out_idx..],
                                "{}",
                                .{readArg(args, i64)},
                            )) |val| val.len else |_| 0;
                        }
                    },
                    'f' => out_idx += if (std.fmt.bufPrint(
                        out[out_idx..],
                        "{}",
                        .{readArg(args, f64)},
                    )) |val| val.len else |_| 0,
                    'p' => out_idx += if (std.fmt.bufPrint(
                        out[out_idx..],
                        "{?}",
                        .{readArg(args, ?*anyopaque)},
                    )) |val| val.len else |_| 0,
                    else => |ch| {
                        if (ch <= '9' and ch >= '0') {
                            while (fmt[in_idx] <= '9' and fmt[in_idx] >= '0') : (in_idx += 1) {}
                            const arg = readArg(args, usize);
                            out_idx += (std.fmt.bufPrint(
                                out[out_idx..],
                                "{x}",
                                .{arg},
                            ) catch unreachable).len;
                            out_idx += 1;
                        } else {
                            _ = readArg(args, *anyopaque);
                            out_idx += 0;
                            in_idx -= 1;
                        }
                    },
                }
            } else {
                out[out_idx] = fmt[in_idx];

                in_idx += 1;
                out_idx += 1;
            }
        }

        const zig_log = std.log.scoped(.@"wayland roots");

        switch (importance) {
            .err => zig_log.err("{s}", .{out[0..out_idx]}),
            .info => zig_log.warn("{s}", .{out[0..out_idx]}),
            .debug => zig_log.info("{s}", .{out[0..out_idx]}),
            .silent => zig_log.debug("{s}", .{out[0..out_idx]}),
            else => {},
        }
    }
};

pub fn init(self: *Session, io: std.Io, environ_map: *std.process.Environ.Map) Error!void {
    wlr.log.init(.debug, &logger.log);

    const wl_server = try wl.Server.create();
    const loop = wl_server.getEventLoop();

    const backend = try wlr.Backend.autocreate(loop, null);
    const scene = try wlr.Scene.create();

    const renderer = try wlr.Renderer.autocreate(backend);
    try renderer.initWlShm(wl_server);

    const compositor = try wlr.Compositor.create(wl_server, 6, renderer);

    const layers = std.EnumArray(Layer, *wlr.SceneTree).init(.{
        .LyrBg = try scene.tree.createSceneTree(),
        .LyrBottom = try scene.tree.createSceneTree(),
        .LyrTileShadows = try scene.tree.createSceneTree(),
        .LyrTile = try scene.tree.createSceneTree(),
        .LyrFloatShadows = try scene.tree.createSceneTree(),
        .LyrFloat = try scene.tree.createSceneTree(),
        .LyrFS = try scene.tree.createSceneTree(),
        .LyrTop = try scene.tree.createSceneTree(),
        .LyrOverlay = try scene.tree.createSceneTree(),
        .LyrDragIcon = try scene.tree.createSceneTree(),
        .LyrBlock = try scene.tree.createSceneTree(),
    });

    try renderer.initServer(wl_server);

    const wlr_allocator = try wlr.Allocator.autocreate(backend, renderer);

    _ = try wlr.Subcompositor.create(wl_server);
    _ = try wlr.DataDeviceManager.create(wl_server);
    _ = try wlr.ExportDmabufManagerV1.create(wl_server);
    _ = try wlr.ScreencopyManagerV1.create(wl_server);
    _ = try wlr.DataControlManagerV1.create(wl_server);
    _ = try wlr.PrimarySelectionDeviceManagerV1.create(wl_server);
    _ = try wlr.Viewporter.create(wl_server);
    _ = try wlr.SinglePixelBufferManagerV1.create(wl_server);
    _ = try wlr.FractionalScaleManagerV1.create(wl_server, 1);
    _ = try wlr.Presentation.create(wl_server, backend, 2);
    _ = try wlr.GammaControlManagerV1.create(wl_server);

    const xdg_activation = try wlr.XdgActivationV1.create(wl_server);

    const output_layout = try wlr.OutputLayout.create(wl_server);

    _ = try wlr.XdgOutputManagerV1.create(wl_server, output_layout);

    // todo: locked bg

    const xdg_shell = try wlr.XdgShell.create(wl_server, 6);

    const layer_shell = try wlr.LayerShellV1.create(wl_server, 3);
    const idle_notifier = try wlr.IdleNotifierV1.create(wl_server);
    const idle_inhibit_manager = try wlr.IdleInhibitManagerV1.create(wl_server);
    const session_lock_manager = try wlr.SessionLockManagerV1.create(wl_server);
    const xdg_decoration_manager = try wlr.XdgDecorationManagerV1.create(wl_server);

    const xwayland = try wlr.Xwayland.create(wl_server, compositor, false);
    const output_manager = try wlr.OutputManagerV1.create(wl_server);

    self.* = .{
        .config = .{
            .lua = .{
                .session = .{
                    .font = .{ .face = try allocator.dupeZ(u8, "monospace") },
                    .session = self,
                },
            },
            .environ_map = environ_map,
            .io = io,
        },

        .environ_map = environ_map,
        .io = io,

        .server = wl_server,
        .backend = backend,
        .scene = scene,
        .renderer = renderer,
        .wlr_allocator = wlr_allocator,
        .output_layout = output_layout,
        .output_manager = output_manager,
        .layers = layers,
        .idle_notifier = idle_notifier,
        .idle_inhibit_manager = idle_inhibit_manager,
        .layer_shell = layer_shell,
        .session_lock_manager = session_lock_manager,
        .compositor = compositor,
        .xdg_shell = xdg_shell,
        .xdg_decoration_manager = xdg_decoration_manager,
        .xdg_activation = xdg_activation,
        .xwayland = xwayland,
        .net_atoms = .initUndefined(),
    };
}

pub fn attachEvents(self: *Session) Error!void {
    signal_session = self;

    self.monitors.init();
    self.clients.init();
    self.focus_clients.init();

    try self.input.init(self);

    try self.config.init();

    _ = try wl.Global.create(self.server, conpositor.LuaManagerV1, 1, *Session, self, IpcManager.managerBind);

    self.output_layout.events.change.add(&self.outputlayout_event.event);

    self.backend.events.new_output.add(&self.newoutput_event.event);

    self.xdg_shell.events.new_toplevel.add(&self.newxdgtoplevel_event.event);
    self.xdg_shell.events.new_surface.add(&self.newxdgsurface_event.event);
    self.xdg_shell.events.new_popup.add(&self.newxdgpopup_event.event);

    self.layer_shell.events.new_surface.add(&self.newlayersurface_event.event);

    self.xdg_decoration_manager.events.new_toplevel_decoration.add(&self.newtopleveldecoration_event.event);

    self.xwayland.?.events.new_surface.add(&self.newxwaylandsurface_event.event);
    self.xwayland.?.events.ready.add(&self.xwaylandready_event.event);

    self.output_manager.events.apply.add(&self.outputmanagerapply_event.event);
    self.output_manager.events.@"test".add(&self.outputmanagertest_event.event);

    self.events_attached = true;
}

pub fn launch(self: *Session) Error!void {
    inline for ([_]std.c.SIG{
        .INT,
        .TERM,
        .PIPE,
    }) |sig| {
        _ = std.c.sigaction(sig, &.{
            .flags = std.c.SA.RESTART,
            .handler = .{ .handler = &handleSignal },
            .mask = std.posix.sigemptyset(),
        }, null);
    }

    var buf: [11]u8 = undefined;
    const socket = try self.server.addSocketAuto(&buf);

    try self.environ_map.put("WAYLAND_DISPLAY", socket);
    try self.environ_map.put("DISPLAY", std.mem.span(self.xwayland.?.display_name));

    try self.config.sourcePath("init.lua");

    try self.backend.start();

    _ = try self.config.sendEvent(?*anyopaque, .startup, null);

    if (self.getObjectsAt(self.input.cursor.x, self.input.cursor.y).monitor) |monitor|
        try self.focusMonitor(monitor);

    self.input.cursor.setXcursor(self.input.xcursor_manager, "default");

    self.server.run();
}

pub fn outputlayout(self: *Session, _: *wlr.OutputLayout) !void {
    return self.updateMons();
}

pub fn updateMons(self: *Session) !void {
    std.log.debug("Update monitors", .{});

    const config = try wlr.OutputConfigurationV1.create();

    {
        var iter = self.monitors.iterator(.forward);
        while (iter.next()) |monitor| {
            if (monitor.output.enabled)
                continue;

            const config_head = try wlr.OutputConfigurationV1.Head.create(config, monitor.output);

            config_head.state.enabled = false;

            self.output_layout.remove(monitor.output);
            try monitor.close();
            monitor.mode = std.mem.zeroes(wlr.Box);
            monitor.window = std.mem.zeroes(wlr.Box);
        }
    }

    {
        var iter = self.monitors.iterator(.forward);
        while (iter.next()) |monitor| {
            if (monitor.output.enabled and
                self.output_layout.get(monitor.output) == null)
            {
                const layout_output = try self.output_layout.addAuto(monitor.output);
                monitor.scene_output.setPosition(layout_output.x, layout_output.y);
            }
        }
    }

    var sgeom: wlr.Box = undefined;
    self.output_layout.getBox(null, &sgeom);

    {
        var iter = self.monitors.iterator(.forward);
        while (iter.next()) |monitor| {
            if (!monitor.output.enabled)
                continue;

            const config_head = try wlr.OutputConfigurationV1.Head.create(config, monitor.output);

            self.output_layout.getBox(monitor.output, &monitor.mode);
            monitor.window = monitor.mode;

            try monitor.arrangeLayers();

            // TODO: update fullscreen client
            monitor.fullscreen_bg.node.setPosition(monitor.mode.x, monitor.mode.y);

            config_head.state.enabled = true;
            config_head.state.mode = monitor.output.current_mode;
            config_head.state.x = monitor.mode.x;
            config_head.state.y = monitor.mode.y;
        }
    }

    if (self.focusedMonitor) |selected| {
        if (selected.output.enabled) {
            var iter = self.clients.iterator(.forward);
            while (iter.next()) |client| {
                if (client.monitor == null and client.isMapped()) {
                    try client.setMonitor(selected);
                }
            }

            if (selected.getFocusedClient()) |client|
                try self.focusClient(client, false)
            else
                self.focusClear();
        }
    }

    self.output_manager.setConfiguration(config);
}

pub fn focusedClient(self: *Session) ?*Client {
    const selected = self.focusedMonitor orelse return null;

    return selected.getFocusedClient();
}

pub fn getSurfaceObjects(self: *Session, surface: *wlr.Surface) ObjectData {
    const root_surface = surface.getRootSurface();

    if (wlr.XwaylandSurface.tryFromWlrSurface(root_surface)) |x_surface|
        return .{
            .tag = @ptrCast(@alignCast(x_surface.data)),
        };

    if (wlr.LayerSurfaceV1.tryFromWlrSurface(root_surface)) |layer_surface|
        return .{
            .tag = @ptrCast(@alignCast(layer_surface.data)),
        };

    var vxdg_surface = wlr.XdgSurface.tryFromWlrSurface(root_surface);
    while (vxdg_surface) |*xdg_surface| {
        switch (xdg_surface.*.role) {
            .popup => {
                if (xdg_surface.*.role_data.popup.?.parent) |parent| {
                    if (wlr.XdgSurface.tryFromWlrSurface(parent)) |parent_surface|
                        vxdg_surface = parent_surface
                    else
                        return self.getSurfaceObjects(parent);
                } else return .{};
            },
            .toplevel => {
                return .{
                    .tag = @ptrCast(@alignCast(xdg_surface.*.data)),
                };
            },
            .none => return .{},
        }
    }

    return .{};
}

pub fn quit(self: *Session) void {
    std.log.info("Quitting Conpositor", .{});
    self.server.terminate();
}

pub fn focusClient(self: *Session, client: *Client, lift: bool) !void {
    const input = self.input;

    if (input.locked)
        return;

    const old_focus = input.seat.keyboard_state.focused_surface;

    if (lift)
        client.raiseToTop();

    if (client.getSurface() == old_focus)
        return;

    const old_client: ?*Client = self.focusedClient();
    if (old_client) |old|
        old.activateSurface(false);

    if (old_focus != null and (client.getSurface() != old_focus)) {
        if (old_focus.? == self.exclusive_focus)
            return;
    }

    if (client.managed) {
        client.focus_link.remove();
        self.focus_clients.prepend(client);
        if (client.surface == .X11)
            client.surface.X11.restack(null, .above);
    }

    if (old_focus != null and (client.getSurface() != old_focus)) {
        if (old_focus.? == self.exclusive_focus)
            return;
    }

    try self.input.motionNotify(0);
    client.notifyEnter(input.seat, input.seat.getKeyboard());
    client.activateSurface(true);
}

pub fn focusClear(self: *Session) void {
    const input = self.input;

    if (input.locked)
        return;

    const old_focus = input.seat.keyboard_state.focused_surface;

    if (old_focus != null and old_focus.? == self.exclusive_focus)
        return;

    const old_client: ?*Client = self.focusedClient();
    if (old_client) |old_focus_client|
        old_focus_client.activateSurface(false);

    self.input.seat.keyboardNotifyClearFocus();
}

pub const ObjectData = struct {
    tag: ?*ObjectTag = null,

    surface_x: f64 = 0.0,
    surface_y: f64 = 0.0,

    monitor: ?*Monitor = null,
};

pub fn getObjectsAt(self: *Session, x: f64, y: f64) ObjectData {
    var result: ObjectData = .{};

    result.monitor = if (self.output_layout.outputAt(x, y)) |output|
        @as(?*Monitor, @ptrCast(@alignCast(output.data)))
    else
        null;

    for (FOCUS_ORDER) |layer_id| {
        const layer = self.layers.get(layer_id);
        const node = layer.node.at(x, y, &result.surface_x, &result.surface_y) orelse
            continue;

        var pnode: ?*wlr.SceneNode = node;
        while (pnode != null and result.tag == null) : (pnode = &pnode.?.parent.?.node) {
            result.tag = @as(?*ObjectTag, @ptrCast(@alignCast(pnode.?.data)));
        }
    }

    return result;
}

pub fn focusStack(self: *Session, dir: CycleDir) !void {
    const sel = self.focusedClient() orelse return;

    if (sel.fullscreen)
        return;

    if (sel.floating)
        return;

    const selmon = sel.monitor orelse return;

    const target = switch (dir) {
        .forward => blk: {
            const IterType = wl.list.Head(Client, .link).Iterator(.forward);
            var iter: IterType = .{ .head = &sel.link, .current = &sel.link, .future = sel.link.next orelse break :blk sel };
            while (iter.next()) |client| {
                if (&client.link == &self.clients.link)
                    continue;
                if (selmon.isClientVisible(client) and
                    client.container == sel.container and
                    !client.floating)
                    break :blk client;
            }

            return;
        },
        .backward => blk: {
            const IterType = wl.list.Head(Client, .link).Iterator(.reverse);
            var iter: IterType = .{ .head = &sel.link, .current = &sel.link, .future = sel.link.next orelse break :blk sel };
            while (iter.next()) |client| {
                if (&client.link == &self.clients.link)
                    continue;
                if (selmon.isClientVisible(client) and
                    client.container == sel.container and
                    !client.floating)
                    break :blk client;
            }

            return;
        },
    };

    try self.focusClient(target, true);
}

pub fn reloadColors(self: *Session) !void {
    var iter = self.clients.iterator(.forward);
    while (iter.next()) |client|
        client.dirty.frame = true;
}

pub fn addIpc(self: *Session, resource: *conpositor.IpcSessionV1) void {
    _ = self;
    _ = resource;
}

var signal_session: ?*Session = null;

pub fn handleSignal(signo: std.c.SIG) callconv(.c) void {
    const session = signal_session orelse return;

    if (signo == .CHLD) {
        var info: std.os.linux.siginfo_t = undefined;
        var tmp: u32 = 0;

        while (std.os.linux.waitid(
            .ALL,
            0,
            &info,
            std.c.W.EXITED | std.c.W.NOHANG | std.c.W.NOWAIT,
            null,
        ) == 0 and
            info.fields.common.first.piduid.pid != 0 and
            (session.xwayland == null or info.fields.common.first.piduid.pid != session.xwayland.?.server.?.pid))
            _ = std.os.linux.waitpid(info.fields.common.first.piduid.pid, &tmp, 0);
    } else if (signo == std.c.SIG.INT or signo == std.c.SIG.TERM) {
        session.server.terminate();
    }
}

fn getAtom(xc: *c.xcb_connection_t, name: [:0]const u8) c.xcb_atom_t {
    var atom: c.xcb_atom_t = 0;
    const cookie = c.xcb_intern_atom(xc, 0, @intCast(name.len), name);
    const reply = c.xcb_intern_atom_reply(xc, cookie, null);
    if (reply != 0)
        atom = reply.*.atom;
    c.free(reply);

    return atom;
}

pub fn xwaylandready(self: *Session) !void {
    const xwayland = self.xwayland orelse return;

    const xc = c.xcb_connect(xwayland.display_name, null) orelse return;
    defer c.xcb_disconnect(xc);
    if (c.xcb_connection_has_error(xc) != 0) {
        std.log.err("xcb connect failed", .{});
    } else {
        self.net_atoms.set(.window_type_dialog, getAtom(xc, "_NET_WM_WINDOW_TYPE_DIALOG"));
        self.net_atoms.set(.window_type_splash, getAtom(xc, "_NET_WM_WINDOW_TYPE_SPLASH"));
        self.net_atoms.set(.window_type_toolbar, getAtom(xc, "_NET_WM_WINDOW_TYPE_TOOLBAR"));
        self.net_atoms.set(.window_type_utility, getAtom(xc, "_NET_WM_WINDOW_TYPE_UTILITY"));
    }

    self.input.xwaylandReady(self.xwayland.?);
}

pub fn focusMonitor(self: *Session, monitor: *Monitor) !void {
    if (self.focusedMonitor == monitor) return;
    if (!monitor.output.enabled) return;

    self.focusedMonitor = monitor;
}
