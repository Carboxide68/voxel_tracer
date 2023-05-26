const std = @import("std");
const log = std.log.scoped(.coxel);
const Renderer = @import("Renderer.zig");
const Tracer = @import("Tracer.zig");
const c = @import("c.zig");

pub fn main() !void {
    const a = std.heap.page_allocator;
    _ = a;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    defer {
        if (@import("builtin").mode == .Debug) {
            if (gpa.detectLeaks()) {
                log.err("Leaks were detected!", .{});
            }
        }
    }

    var renderer = try Renderer.init();
    defer renderer.deinit();

    var tracer = try Tracer.init(gpa.allocator());
    defer tracer.destroy();

    try Tracer.tester();
    tracer.addCube(
        .{ .x = 0, .y = 0, .z = 3 },
        0.1,
        .{ .x = 1, .y = 0, .z = 0 },
    );
    tracer.addCube(
        .{ .x = 2, .y = 0, .z = 3 },
        0.1,
        .{ .x = 0, .y = 1, .z = 0 },
    );
    tracer.addCube(
        .{ .x = 0.50, .y = 0, .z = 1 },
        0.1,
        .{ .x = 0, .y = 0, .z = 1 },
    );
    tracer.camera.fov = [2]f32{ 70, 70 };

    while (renderer.draw_frame()) {
        _ = c.igBegin("Custom Window", 0, 0);
        if (Renderer.button("Trace Scene")) {
            log.info("Tracing scene...", .{});
            tracer.traceScene();
        }
        if (Renderer.button("Clear scene")) {
            log.info("Clearing scene...", .{});
            tracer.clearImage();
        }
        _ = c.igSliderFloat("Variance", &tracer.variance, 0, 0.01, "%.5f", c.ImGuiSliderFlags_Logarithmic);
        c.igText("Trace Time: %dus", @divFloor(Tracer.Timings.trace_scene, 1000));
        tracer.draw();
        c.igEnd();
    }
}
