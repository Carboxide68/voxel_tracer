const std = @import("std");
const log = std.log.scoped(.coxel);
const Renderer = @import("Renderer.zig");
const Tracer = @import("Tracer.zig");
const c = @import("c.zig");

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const a = allocator.allocator();

    var renderer = try Renderer.init();
    defer renderer.deinit();

    var tracer = try Tracer.init(a);
    defer tracer.destroy();

    tracer.addCube(
        .{ .x = 0, .y = 0, .z = 3 },
        0.25,
        .{ .x = 0.7, .y = 0.5, .z = 0.2 },
    );
    tracer.addCube(
        .{ .x = 2, .y = 0, .z = 3 },
        0.25,
        .{ .x = 0.2, .y = 0.5, .z = 0.7 },
    );

    while (renderer.draw_frame()) {
        _ = c.igBegin("Custom Window", 0, 0);
        if (Renderer.button("Trace Scene")) {
            tracer.trace_scene();
        }

        tracer.draw();
        c.igEnd();
    }
}
