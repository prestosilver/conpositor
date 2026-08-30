const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Client = @import("Client.zig");
const LayerSurface = @import("LayerSurface.zig");

pub const ObjectTag = enum {
    client,
    client_frame,
    client_shadow,
    layer_surface,

    pub fn toClient(self: *ObjectTag) ?*Client {
        // could also impl for client frame

        if (self.* == .client)
            return @as(*Client, @alignCast(@fieldParentPtr("object_tag", self)));

        if (self.* == .client_frame) {
            const frame: *Client.ClientFrame = @alignCast(@fieldParentPtr("object_tag", self));
            return @fieldParentPtr("frame", frame);
        }

        if (self.* == .client_shadow) {
            const frame: *Client.ClientFrame = @alignCast(@fieldParentPtr("shadow_tag", self));
            return @fieldParentPtr("frame", frame);
        }

        return null;
    }

    pub fn toLayerSurface(self: *ObjectTag) ?*LayerSurface {
        // could also impl for client frame

        if (self.* == .layer_surface)
            return @alignCast(@fieldParentPtr("object_tag", self));

        return null;
    }

    pub fn getBounds(self: *ObjectTag) ?wlr.Box {
        if (self.toClient()) |client|
            return client.getInnerBounds();

        if (self.toLayerSurface()) |layer_surface|
            return layer_surface.bounds;

        return null;
    }

    pub fn getSurface(self: *ObjectTag) ?*wlr.Surface {
        if (self.toClient()) |client|
            return switch (client.surface) {
                .XDG => |xdg_surf| xdg_surf.surface,
                .X11 => |x_surf| x_surf.surface,
            };

        if (self.toLayerSurface()) |layer_surface|
            return layer_surface.surface.surface;

        return null;
    }
};
