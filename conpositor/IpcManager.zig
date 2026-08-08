const wl = @import("wayland").server.wl;
const conpositor = @import("wayland").server.conpositor;
const wlr = @import("wlroots");
const std = @import("std");

const Monitor = @import("Monitor.zig");
const Session = @import("Session.zig");
const Config = @import("Config.zig");

const allocator = Config.allocator;

pub fn managerBind(client: *wl.Client, session: *Session, version: u32, id: u32) void {
    const lua_runner_resource = conpositor.LuaManagerV1.create(client, version, id) catch {
        client.postNoMemory();
        std.log.err("out of memory", .{});
        return;
    };

    lua_runner_resource.setHandler(*Session, handleRunnerRequest, null, session);
}

const RunnerHandler = struct {
    session: *Session,
};

fn handleRunnerRequest(
    manager: *conpositor.LuaManagerV1,
    request: conpositor.LuaManagerV1.Request,
    session: *Session,
) void {
    switch (request) {
        .create_runner => createRunner(manager, request, session) catch |err| switch (err) {
            error.OutOfMemory => manager.getClient().postNoMemory(),
            else => manager.getClient().postImplementationError(@errorName(err)),
        },
    }
}

fn createRunner(
    manager: *conpositor.LuaManagerV1,
    request: conpositor.LuaManagerV1.Request,
    session: *Session,
) !void {
    const req = request.create_runner;

    std.log.debug("Create runner", .{});

    const resource = try conpositor.LuaRunnerV1.create(
        manager.getClient(),
        manager.getVersion(),
        req.id,
    );

    const runner = try allocator.create(RunnerHandler);
    runner.* = .{
        .session = session,
    };

    resource.setHandler(*RunnerHandler, handleOutputRequest, null, runner);
}

fn handleOutputRequest(
    runner: *conpositor.LuaRunnerV1,
    request: conpositor.LuaRunnerV1.Request,
    handler: *RunnerHandler,
) void {
    switch (request) {
        .begin => beginRunner(runner, request, handler) catch |err| switch (err) {
            error.OutOfMemory => runner.getClient().postNoMemory(),
            else => runner.getClient().postImplementationError(@errorName(err)),
        },
    }
}
pub fn beginRunner(
    runner: *conpositor.LuaRunnerV1,
    request: conpositor.LuaRunnerV1.Request,
    handler: *RunnerHandler,
) !void {
    const req = request.begin;

    const return_command = try std.fmt.allocPrint(allocator, "{s}", .{req.command});
    defer allocator.free(return_command);

    var result = try handler.session.config.run(return_command);
    defer result.deinit();

    if (result.failed)
        runner.sendFail(result.result orelse "")
    else if (result.result) |res|
        runner.sendReturn(res)
    else
        runner.sendSuccess();
}
