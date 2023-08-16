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
    tracer.camera.position = .{ .d = .{ 0, 1, 0 } };
    tracer.camera.lookAt(.{ .d = .{ 1.8, 0, 3 } });

    Tracer.tester() catch |err| {
        log.warn("Tests failed! Err: {}", .{err});
    };
    tracer.addCube(
        .{ .d = .{ 0, 0.1, 3 } },
        0.1,
        .{ .color = .{ .d = .{ 1, 0, 0 } } },
    );
    tracer.addCube(
        .{ .d = .{ 2, 0.1, 3 } },
        0.1,
        .{
            .color = .{ .d = .{ 0, 1, 0 } },
            .scatter_variance = 0,
        },
    );
    tracer.addCube(
        .{ .d = .{ 1.8, 0.1, 3.3 } },
        0.1,
        .{
            .color = .{ .d = .{ 0, 0, 0 } },
            .scatter_variance = 0.7,
        },
    );
    tracer.addCube(
        .{ .d = .{ 0.50, 0.1, 1 } },
        0.1,
        .{ .color = .{ .d = .{ 0, 0, 1 } } },
    );
    tracer.addCube(
        .{ .d = .{ 0, -5.01, 0 } },
        5,
        .{ .color = .{ .d = .{ 0.7, 0.7, 0.7 } } },
    );

    var size_coefficient: f32 = 0.6;
    while (renderer.draw_frame()) {
        _ = c.igBegin("Custom Window", 0, 0);
        if (Renderer.button("Trace Scene")) {
            tracer.traceScene();
        }
        if (Renderer.button("Clear scene")) {
            log.info("Clearing scene...", .{});
            tracer.clearImage();
        }
        if (Renderer.button("Resize")) {
            const size = renderer.window.getFramebufferSize();
            tracer.resize(
                @as(u32, @intFromFloat(@as(f32, @floatFromInt(size.width)) * size_coefficient)),
                @as(u32, @intFromFloat(@as(f32, @floatFromInt(size.height)) * size_coefficient)),
            );
        }
        _ = c.igSliderFloat("Variance", &tracer.variance, 0, 0.01, "%.5f", c.ImGuiSliderFlags_Logarithmic);
        _ = c.igSliderFloat("Size coefficient", &size_coefficient, 0.3, 4, "%.2f", 0);
        _ = c.igSliderFloat("Depth Of Field", &tracer.camera.dof, 0, 10, "%.3f", 0);
        _ = c.igInputInt("Max Depth", @as([*c]c_int, @ptrCast(&tracer.max_depth)), 1, 2, 0);
        c.igText("Trace Time: %dus", @divFloor(Tracer.Timings.trace_scene, 1000));
        tracer.draw();
        c.igEnd();
    }
}
