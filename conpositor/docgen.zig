const std = @import("std");

const LUA_TYPES = @import("LuaContext.zig").LUA_TYPES;

var dbg_allocator: std.heap.DebugAllocator(.{}) = .init;
const allocator = dbg_allocator.allocator();

pub fn main(init: std.process.Init) !void {
    var args_arena: std.heap.ArenaAllocator = .init(allocator);
    defer args_arena.deinit();

    const args_allocator = args_arena.allocator();
    const args = try init.minimal.args.toSlice(args_allocator);

    if (args.len != 2) return error.InvalidArguments;
    const path = args[1];

    std.Io.Dir.createDir(.cwd(), init.io, path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const root = try std.Io.Dir.openDir(.cwd(), init.io, path, .{});
    defer root.close(init.io);

    const all = try root.createFile(init.io, "all.lua", .{});
    defer all.close(init.io);

    var all_writer = all.writer(init.io, &.{});

    inline for (LUA_TYPES) |lua_type| {
        try all_writer.interface.print(
            \\---@class {s}
            \\---{s}
            \\
        , .{
            lua_type.lua_name,
            lua_type.description,
        });

        inline for (.{ .getter, .setter, .method, .function }) |check| {
            for (lua_type.methods) |method| {
                if (check != method.kind)
                    continue;

                const new_desc = try std.mem.replaceOwned(u8, allocator, method.description, "\n", "\n---");
                defer allocator.free(new_desc);

                if (method.kind == .setter) {
                    if (for (lua_type.methods) |other_method| {
                        if (std.mem.eql(u8, method.lua_name, other_method.lua_name) and other_method.kind == .getter)
                            break true;
                    } else false) continue;
                }

                switch (method.kind) {
                    .getter, .setter => {
                        const text = try std.fmt.allocPrint(allocator,
                            \\---@field {s} {s} {s}
                            \\
                        , .{ method.lua_name, if (method.returns) |ret| ret.kind else "any", new_desc });
                        defer allocator.free(text);
                        try all_writer.interface.writeAll(text);
                    },
                    .method => {
                        try all_writer.interface.print(
                            \\---{s}
                            \\
                        , .{new_desc});

                        for (method.params) |param| {
                            try all_writer.interface.print(
                                \\---@param {s} {s} {s}
                                \\
                            , .{ param.name, param.kind, param.desc });
                        }

                        if (method.returns) |returns| {
                            try all_writer.interface.print(
                                \\---@return {s} {s} {s}
                                \\
                            , .{ returns.kind, returns.name, returns.desc });
                        }

                        try all_writer.interface.print(
                            \\function {s}:{s}(
                        , .{ lua_type.lua_name, method.lua_name });

                        var first = true;
                        for (method.params) |param| {
                            if (!first)
                                try all_writer.interface.writeAll(", ");

                            try all_writer.interface.writeAll(param.name);

                            first = false;
                        }

                        try all_writer.interface.writeAll(") end\n");
                    },
                    .function => {
                        for (method.params) |param| {
                            try all_writer.interface.print(
                                \\---{s}
                                \\---@param {s} {s} {s}
                                \\
                            , .{ new_desc, param.name, param.kind, param.desc });
                        }

                        if (method.returns) |returns| {
                            try all_writer.interface.print(
                                \\---@return {s} {s} {s}
                                \\
                            , .{ returns.kind, returns.name, returns.desc });
                        }

                        try all_writer.interface.print(
                            \\function {s}.{s}(
                        , .{ lua_type.lua_name, method.lua_name });

                        var first = true;
                        for (method.params) |param| {
                            if (!first)
                                try all_writer.interface.writeAll(", ");

                            try all_writer.interface.writeAll(param.name);

                            first = false;
                        }

                        try all_writer.interface.writeAll(") end\n");
                    },
                    .hidden_function => {
                        // Hidden functions are un documented.
                    },
                }
            }

            if (check == .setter) {
                try all_writer.interface.print(
                    \\{s} = {{}}
                    \\
                , .{
                    lua_type.lua_name,
                });
            }
        }

        try all_writer.interface.writeAll("\n");
    }

    try all_writer.interface.writeAll(@embedFile("lua/defn_extensions.lua"));
}
