const wl = @import("wayland").server.wl;
const ztracy = @import("ztracy");

// This is used to abstract away wayland events, allowing for consistent profiling
// and hiding the @fieldParentPtr calls from most users
pub fn Event(comptime Data: type, comptime name: []const u8, comptime Base: type) type {
    return struct {
        const Self = @This();

        event: wl.Listener(Data) = .init(callback),

        const callback = (if (Data == void) struct {
            pub fn callback(listener: *wl.Listener(void)) void {
                // tracy tracing
                const tracy_zone = ztracy.ZoneNC(@src(), @typeName(Base) ++ ":" ++ name ++ "_event", 0x00_ff_00_00);
                defer tracy_zone.End();

                // get the pointer to the base class this event is tied to
                const ev: *Self = @fieldParentPtr("event", listener);
                const self: *Base = @fieldParentPtr(name ++ "_event", ev);

                // return here just to make sure no code ends up after this
                return (@field(Base, name))(self) catch |ex|
                    @panic(@errorName(ex));
            }
        } else struct {
            pub fn callback(listener: *wl.Listener(Data), data: Data) void {
                // tracy tracing
                const tracy_zone = ztracy.ZoneNC(@src(), @typeName(Base) ++ ":" ++ name ++ "_event", 0x00_ff_00_00);
                defer tracy_zone.End();

                // get the pointer to the base class this event is tied to
                const ev: *Self = @fieldParentPtr("event", listener);
                const self: *Base = @fieldParentPtr(name ++ "_event", ev);

                // return here just to make sure no code ends up after this
                return (@field(Base, name))(self, data) catch |ex|
                    @panic(@errorName(ex));
            }
        }).callback;
    };
}
