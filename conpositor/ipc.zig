const wl = @import("wayland").server.wl;
const conpositor = @import("wayland").server.conpositor;
const wlr = @import("wlroots");
const std = @import("std");

const Monitor = @import("monitor.zig");
const Session = @import("session.zig");
const Config = @import("config.zig");

const allocator = Config.allocator;

pub fn managerBind(client: *wl.Client, session: *Session, version: u32, id: u32) void {
    const ipc_manager_resource = conpositor.IpcManagerV1.create(client, version, id) catch {
        client.postNoMemory();
        std.log.err("out of memory", .{});
        return;
    };

    ipc_manager_resource.setHandler(*Session, handleManagerRequest, null, session);
}

fn handleManagerRequest(
    manager: *conpositor.IpcManagerV1,
    request: conpositor.IpcManagerV1.Request,
    session: *Session,
) void {
    switch (request) {
        .destroy => manager.destroy(),
        .get_output => |req| {
            const wlr_output = wlr.Output.fromWlOutput(req.output) orelse return;
            const monitor: *Monitor = @ptrCast(@alignCast(wlr_output.data));

            const resource = conpositor.IpcOutputV1.create(
                manager.getClient(),
                manager.getVersion(),
                req.id,
            ) catch {
                manager.getClient().postNoMemory();
                std.log.err("out of memory", .{});
                return;
            };

            resource.setHandler(?*anyopaque, handleOutputRequest, handleOutputDestroy, null);

            monitor.addIpc(resource);
        },
        .get_session => |req| {
            const resource = conpositor.IpcSessionV1.create(
                manager.getClient(),
                manager.getVersion(),
                req.id,
            ) catch {
                manager.getClient().postNoMemory();
                std.log.err("out of memory", .{});
                return;
            };

            resource.setHandler(*Session, handleSessionRequest, null, session);

            session.addIpc(resource);
        },
    }
}

fn handleSessionRequest(
    manager: *conpositor.IpcSessionV1,
    request: conpositor.IpcSessionV1.Request,
    session: *Session,
) void {
    handleSessionRequestInternal(manager, request, session) catch |err|
        switch (err) {
            error.OutOfMemory => {
                manager.getClient().postNoMemory();
                std.log.err("out of memory", .{});
            },
            else => return,
        };
}

fn handleSessionRequestInternal(
    manager: *conpositor.IpcSessionV1,
    request: conpositor.IpcSessionV1.Request,
    session: *Session,
) !void {
    switch (request) {
        .destroy => manager.destroy(),
        .run_command => |req| {
            const command = std.mem.span(req.command);

            const resource = try conpositor.CommandOutputV1.create(
                manager.getClient(),
                manager.getVersion(),
                req.id,
            );
            defer resource.destroy();

            const return_command = try std.fmt.allocPrint(allocator, "return {s}", .{command});
            defer allocator.free(return_command);

            const result = try session.config.run(return_command);

            if (result.failed)
                resource.sendFail(result.result)
            else
                resource.sendSuccess(result.result);
        },
        .get_focused_output => |req| {
            if (session.focusedMonitor) |monitor| {
                const resource = conpositor.IpcOutputV1.create(
                    manager.getClient(),
                    manager.getVersion(),
                    req.id,
                ) catch {
                    manager.getClient().postNoMemory();
                    std.log.err("out of memory", .{});
                    return;
                };

                resource.setHandler(?*anyopaque, handleOutputRequest, handleOutputDestroy, null);

                monitor.addIpc(resource);
            }
        },
    }
}

fn handleOutputDestroy(
    manager: *conpositor.IpcOutputV1,
    _: ?*anyopaque,
) void {
    manager.getLink().remove();
}

fn handleOutputRequest(
    manager: *conpositor.IpcOutputV1,
    request: conpositor.IpcOutputV1.Request,
    _: ?*anyopaque,
) void {
    _ = manager;
    switch (request) {
        else => {},
        // .destroy => manager.destroy(),
    }
}
