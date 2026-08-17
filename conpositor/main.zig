const std = @import("std");
const builtin = @import("builtin");

const Session = @import("Session.zig");
const Config = @import("Config.zig");

pub const std_options = std.Options{
    // I wanna share loggers with wayland
    .logFn = Config.conpositorLogFn,
};

// The only errors this program can return
const ConpositorError =
    Session.Error ||
    Config.Error;

// This main function should only construct the high level storage types
pub fn main(init: std.process.Init) ConpositorError!void {
    defer Config.allocator_data.deinit();

    var session: Session = undefined;
    try session.init(init.io, init.environ_map);
    defer session.deinit();

    try session.attachEvents();

    try session.launch();
}
