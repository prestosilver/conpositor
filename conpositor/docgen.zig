const std = @import("std");

// This is used to generate lsp docs from the lua types defined in the context file.
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
        const class_text = try std.fmt.allocPrint(allocator,
            \\---@class {s}
            \\---{s}
            \\
        , .{
            lua_type.lua_name,
            lua_type.description,
        });
        defer allocator.free(class_text);
        try all_writer.interface.writeAll(class_text);

        for (lua_type.methods) |method| {
            switch (method.kind) {
                .getter => {
                    const new_desc = try std.mem.replaceOwned(u8, allocator, method.description, "\n", "\n---");
                    defer allocator.free(new_desc);

                    const text = try std.fmt.allocPrint(allocator,
                        \\---@field {s} any {s}
                        \\
                    , .{ method.lua_name, new_desc });
                    defer allocator.free(text);
                    try all_writer.interface.writeAll(text);
                },
                .setter => {},
                .method => {
                    const new_desc = try std.mem.replaceOwned(u8, allocator, method.description, "\n", "\n---");
                    defer allocator.free(new_desc);

                    const text = try std.fmt.allocPrint(allocator,
                        \\---@param self {s}
                        \\---{s}
                        \\function {s}.{s}(self, ...)end
                        \\
                    , .{ lua_type.lua_name, new_desc, lua_type.lua_name, method.lua_name });
                    defer allocator.free(text);
                    try all_writer.interface.writeAll(text);
                },
                .function => {
                    const new_desc = try std.mem.replaceOwned(u8, allocator, method.description, "\n", "\n---");
                    defer allocator.free(new_desc);

                    const text = try std.fmt.allocPrint(allocator,
                        \\---{s}
                        \\function {s}.{s}(...)end
                        \\
                    , .{ new_desc, lua_type.lua_name, method.lua_name });
                    defer allocator.free(text);
                    try all_writer.interface.writeAll(text);
                },
            }
        }

        const global_text = try std.fmt.allocPrint(allocator,
            \\{s} = {{}}
            \\
        , .{
            lua_type.lua_name,
        });
        defer allocator.free(global_text);
        try all_writer.interface.writeAll(global_text);

        try all_writer.interface.writeAll("\n");
    }

    {
        try all_writer.interface.writeAll(
            \\session = Session
            \\
        );
    }
}
