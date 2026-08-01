const std = @import("std");
const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Wayland protocols to zig
    const scanner = Scanner.create(b, .{});
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("stable/tablet/tablet-v2.xml");
    scanner.addSystemProtocol("staging/cursor-shape/cursor-shape-v1.xml");
    scanner.addSystemProtocol("staging/ext-session-lock/ext-session-lock-v1.xml");
    scanner.addSystemProtocol("staging/tearing-control/tearing-control-v1.xml");
    scanner.addSystemProtocol("unstable/pointer-constraints/pointer-constraints-unstable-v1.xml");
    scanner.addSystemProtocol("unstable/pointer-gestures/pointer-gestures-unstable-v1.xml");
    scanner.addSystemProtocol("unstable/xdg-decoration/xdg-decoration-unstable-v1.xml");

    scanner.addCustomProtocol(b.path("protocol/conpositor-ipc-unstable-v1.xml"));
    scanner.addCustomProtocol(b.path("protocol/wlr-layer-shell-unstable-v1.xml"));

    // Some of these versions may be out of date with what wlroots implements.
    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_subcompositor", 1);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("wl_data_device_manager", 3);

    scanner.generate("xdg_wm_base", 2);
    scanner.generate("zwp_pointer_gestures_v1", 3);
    scanner.generate("zwp_pointer_constraints_v1", 1);
    scanner.generate("zwp_tablet_manager_v2", 1);
    scanner.generate("zxdg_decoration_manager_v1", 2);
    scanner.generate("ext_session_lock_manager_v1", 1);
    scanner.generate("wp_cursor_shape_manager_v1", 1);
    scanner.generate("wp_tearing_control_manager_v1", 1);

    scanner.generate("zwlr_layer_shell_v1", 4);
    scanner.generate("conpositor_ipc_manager_v1", 1);

    const wayland_mod = b.createModule(.{
        .root_source_file = scanner.result,
        .target = target,
        .optimize = optimize,
    });

    // external mods
    const xkbcommon_dep = b.dependency("xkbcommon", .{});
    const known_folders_dep = b.dependency("known_folders", .{});
    const pixman_dep = b.dependency("pixman", .{});
    const wlroots_dep = b.dependency("wlroots", .{});
    const cairo_dep = b.dependency("cairo", .{});
    const lua_dep = b.dependency("zlua", .{
        .shared = true,
        .lang = .lua55,
    });

    wlroots_dep.module("wlroots").addImport("wayland", wayland_mod);
    wlroots_dep.module("wlroots").addImport("xkbcommon", xkbcommon_dep.module("xkbcommon"));
    wlroots_dep.module("wlroots").addImport("pixman", pixman_dep.module("pixman"));

    wlroots_dep.module("wlroots").resolved_target = target;
    wlroots_dep.module("wlroots").optimize = optimize;
    wlroots_dep.module("wlroots").linkSystemLibrary("wlroots-0.20", .{});

    // Conpositor its self
    const conpositor = b.addExecutable(.{
        .name = "conpositor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("conpositor/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "wayland", .module = wayland_mod },
                .{ .name = "xkbcommon", .module = xkbcommon_dep.module("xkbcommon") },
                .{ .name = "wlroots", .module = wlroots_dep.module("wlroots") },
                .{ .name = "cairo", .module = cairo_dep.module("cairo") },
                .{ .name = "pixman", .module = pixman_dep.module("pixman") },
                .{ .name = "zlua", .module = lua_dep.module("zlua") },
                .{ .name = "known-folders", .module = known_folders_dep.module("known-folders") },
            },
        }),
    });

    conpositor.root_module.linkSystemLibrary("lua", .{});
    conpositor.root_module.linkSystemLibrary("wayland-server", .{});
    conpositor.root_module.linkSystemLibrary("xcb", .{});
    conpositor.root_module.linkSystemLibrary("libinput", .{});
    conpositor.root_module.linkSystemLibrary("xkbcommon", .{});
    conpositor.root_module.linkSystemLibrary("pixman-1", .{});

    const lib_step = b.addInstallDirectory(.{
        .source_dir = b.path("libs"),
        .install_dir = .{ .custom = "share/conpositor" },
        .install_subdir = "lib",
    });

    // TODO: generate types
    // const types_step = b.addInstallDirectory(.{
    //     .source_dir = b.path("types"),
    //     .install_dir = .{ .custom = "share/conpositor" },
    //     .install_subdir = "config",
    // });

    const config_step = b.addInstallDirectory(.{
        .source_dir = b.path("config"),
        .install_dir = .{ .custom = "share/conpositor" },
        .install_subdir = "config",
    });

    const conpositor_step = b.addInstallArtifact(conpositor, .{});
    conpositor_step.step.dependOn(&lib_step.step);
    conpositor_step.step.dependOn(&config_step.step);

    b.getInstallStep().dependOn(&conpositor_step.step);

    // IPC utility
    const conpositormsg = b.addExecutable(.{
        .name = "conpositor-msg",
        .root_module = b.createModule(.{
            .root_source_file = b.path("conpositormsg/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "wayland", .module = wayland_mod },
            },
        }),
    });

    conpositormsg.root_module.linkSystemLibrary("wayland-client", .{});

    b.installArtifact(conpositormsg);

    // run step
    const run_cmd = b.addRunArtifact(conpositor);
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.setEnvironmentVariable("CONPOSITOR_LIB_DIR", b.getInstallPath(.{ .custom = "share/conpositor" }, ""));

    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // IPC util run step
    const run_msg = b.addRunArtifact(conpositormsg);
    run_msg.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_msg.addArgs(args);

    const run_msg_step = b.step("runmsg", "Run the messager app");
    run_msg_step.dependOn(&run_msg.step);

    // Creates a step for unit testing. This only builds the test executable
    const conpositor_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("conpositor/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const conpositor_msg_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("conpositormsg/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_conpositor_unit_tests = b.addRunArtifact(conpositor_unit_tests);
    const run_conpositor_msg_unit_tests = b.addRunArtifact(conpositor_msg_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_conpositor_unit_tests.step);
    test_step.dependOn(&run_conpositor_msg_unit_tests.step);
}
