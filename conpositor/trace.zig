const std = @import("std");
const wl = @import("wayland").server.wl;
const ztracy = @import("ztracy");

// This is used to abstract away wayland events, allowing for consistent profiling
// and hiding the @fieldParentPtr calls from most users
pub fn Event(comptime Data: type, comptime name: []const u8, comptime Base: type) type {
    return struct {
        const Self = @This();

        event: wl.Listener(Data) = .init(callback),

        const color = blk: {
            var out = 0;
            for (@typeName(Base), 0..) |c, idx| {
                out += @as(u32, @intCast(c)) * .{ 0x1, 0x1_00, 0x1_00_00 }[idx % 3];
            }

            break :blk out;
        };

        const callback = (if (Data == void) struct {
            pub fn callback(listener: *wl.Listener(void)) void {
                const src = comptime blk: {
                    var tmp = @src();
                    tmp.fn_name = @typeName(Base) ++ ":" ++ name ++ "_event";
                    break :blk tmp;
                };

                // tracy tracing
                const tracy_zone = ztracy.ZoneNC(src, @typeName(Base) ++ ":" ++ name ++ "_event", color);
                defer tracy_zone.End();

                std.log.debug(@typeName(Base) ++ ":" ++ name ++ "_event", .{});

                // get the pointer to the base class this event is tied to
                const ev: *Self = @fieldParentPtr("event", listener);
                const self: *Base = @fieldParentPtr(name ++ "_event", ev);

                // return here just to make sure no code ends up after this
                return @call(.always_inline, @field(Base, name), .{self}) catch |ex|
                    @panic(@errorName(ex));
            }
        } else struct {
            pub fn callback(listener: *wl.Listener(Data), data: Data) void {
                const src = comptime blk: {
                    var tmp = @src();
                    tmp.fn_name = @typeName(Base) ++ ":" ++ name ++ "_event";
                    break :blk tmp;
                };

                // tracy tracing
                const tracy_zone = ztracy.ZoneNC(src, @typeName(Base) ++ ":" ++ name ++ "_event", color);
                defer tracy_zone.End();

                std.log.debug(@typeName(Base) ++ ":" ++ name ++ "_event", .{});

                // get the pointer to the base class this event is tied to
                const ev: *Self = @fieldParentPtr("event", listener);
                const self: *Base = @fieldParentPtr(name ++ "_event", ev);

                // return here just to make sure no code ends up after this
                return @call(.always_inline, @field(Base, name), .{ self, data }) catch |ex|
                    @panic(@errorName(ex));
            }
        }).callback;
    };
}
