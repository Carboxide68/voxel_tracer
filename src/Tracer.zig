const std = @import("std");
const log = std.log.scoped(.coxel);

const vector = @import("utils/vector.zig");
const FPrec = f32;
const Vec2 = vector.Vec2T(FPrec);
const Vec3 = vector.Vec3T(FPrec);
const Vec4 = vector.Vec4T(FPrec);

const buffer = @import("utils/buffer.zig");
const Buffer = buffer.Buffer;
const VertexArray = buffer.VertexArray;
const Shader = @import("utils/shader.zig").Shader;
const Camera = @import("Camera.zig");
const Ray = Camera.Ray;

const Tracer = @This();

pub const Box = struct {
    min: Vec3,
    max: Vec3,
};

pub const Hit = struct {
    position: Vec3,
    hit_index: u32,
};

a: std.mem.Allocator,

boxes: std.ArrayList(Box),
colors: std.ArrayList(Vec3),

camera: Camera,

vao: VertexArray,
vertex_buffer: Buffer,
image_buffer: Buffer,
drawer: Shader,

frame: [2]u32,
pixels: []Vec4,
clear_color: Vec4,

pub fn init(a: std.mem.Allocator) !Tracer {
    var self: Tracer = undefined;
    self.boxes = std.ArrayList(Box).init(a);
    self.colors = std.ArrayList(Vec3).init(a);
    self.vao = VertexArray.init();
    self.vertex_buffer = Buffer.init(@sizeOf(f32) * 12, .static_draw);
    try self.vertex_buffer.subData(
        0,
        @sizeOf(f32) * 12,
        &[_]f32{ 1, -1, -1, -1, -1, 1, -1, 1, 1, 1, 1, -1 },
    );
    self.vao.bindVertexBuffer(self.vertex_buffer, 0, 0, @sizeOf(f32) * 2);
    self.vao.setLayout(0, 2, 0, .float);
    self.frame = [2]u32{ 480, 680 };
    self.pixels = try a.alloc(Vec4, self.frame[0] * self.frame[1]);
    @memset(self.pixels, comptime Vec4.init(0));
    self.image_buffer = Buffer.init(@sizeOf([4]f32) * self.frame[0] * self.frame[1], .dynamic_draw);
    self.drawer = try Shader.initFile("src/shaders/image_drawer.os", a);
    self.a = a;
    self.clear_color = Vec4.fromData(.{ 0.5, 0.5, 0, 0 });
    self.camera = Camera.init(
        Vec3.fromData(.{ 0, 0, 0 }),
        Vec3.fromData(.{ 0, 0, 1 }),
        [2]f32{ 60, 60 },
    );
    return self;
}

pub fn destroy(self: *Tracer) void {
    self.boxes.deinit();
    self.colors.deinit();
    self.drawer.destroy();
    self.vao.destroy();
    self.vertex_buffer.destroy();
    self.image_buffer.destroy();
}

pub fn addCube(self: *Tracer, pos: Vec3, s: FPrec, color: Vec3) void {
    self.boxes.append(.{
        .max = pos.sAdd(s),
        .min = pos.sSub(s),
    }) catch |err| log.err("Failed to add to array! Error: {}", .{err});
    self.colors.append(color) catch |err| log.err("Failed to add to array! Error: {}", .{err});
}

pub fn addBox(self: *Tracer, min: Vec3, max: Vec3, color: Vec3) void {
    self.boxes.append(.{
        .min = min,
        .max = max,
    }) catch |err| log.err("Failed to add to array! Error: {}", .{err});
    self.colors.append(color) catch |err| log.err("Failed to add to array! Error: {}", .{err});
}

pub fn trace_scene(self: *Tracer) void {
    const w = @intToFloat(f32, self.frame[0]);
    const h = @intToFloat(f32, self.frame[1]);
    for (0..self.frame[1]) |i| {
        for (self.pixels[self.frame[0] * i .. self.frame[0] * (i + 1)], i * self.frame[0]..) |*pixel, k| {
            const rel_pos = [2]f32{
                @intToFloat(f32, k) / w,
                @intToFloat(f32, i) / h,
            };
            const maybe_hit = self.trace(self.camera.castRay(rel_pos));
            if (maybe_hit) |_| {
                pixel.* = Vec4.fromData(.{ 1, 1, 1, 1 });
            } else {
                pixel.* = self.clear_color;
            }
        }
    }
    self.image_buffer.subData(
        0,
        @sizeOf(Vec4) * self.frame[0] * self.frame[1],
        self.pixels,
    ) catch |err| {
        log.err("Failed to upload image to GPU buffer! Error: {}", .{err});
    };
}

pub fn draw(self: *Tracer) void {
    self.drawer.bind();
    self.drawer.uniform(self.frame[0], "u_x_size");
    self.drawer.uniform(self.frame[1], "u_y_size");
    self.image_buffer.bindAll(.shader_storage, 0) catch unreachable;
    self.vao.drawArrays(.triangles, 0, 6);
}

pub fn trace(self: Tracer, ray: Ray) ?Hit {
    const pos = ray.origin;
    const n_inv = Vec3.fromData(.{ 1 / ray.direction.x, 1 / ray.direction.y, 1 / ray.direction.z });
    return hit_blk: for (self.boxes.items, 0..) |box, i| {
        const t1 = Vec3.fromSimd((box.min.simd() - pos.simd()) * n_inv.simd());
        const t2 = Vec3.fromSimd((box.max.simd() - pos.simd()) * n_inv.simd());
        const tmax = @max(@reduce(.Max, t1.simd()), @reduce(.Max, t2.simd()));
        const tmin = @min(@reduce(.Min, t1.simd()), @reduce(.Min, t2.simd()));

        if (tmax >= tmin and tmax >= 0) {
            var hit_pos: Vec3 = undefined;
            if (tmin < 0) {
                hit_pos = pos.add(ray.direction.sMult(tmax));
            } else {
                hit_pos = pos.add(ray.direction.sMult(tmin));
            }
            break :hit_blk Hit{ .position = hit_pos, .hit_index = @intCast(u32, i) };
        }
    } else {
        break :hit_blk null;
    };
}

test "Tracing" {
    const a = std.testing.allocator;
    var tracer = try Tracer.init(a);
    tracer.addCube(Vec3.fromData(.{
        0,
        0,
        1,
    }));
    std.testing.expect(tracer.trace(Ray{
        .origin = Vec3{ .x = 0, .y = 0, .z = 0 },
        .direction = Vec3{ .x = 0, .y = 0, .z = 1 },
    }) != null);
    std.testing.expect(tracer.trace(Ray{
        .origin = Vec3{ .x = 0, .y = 0, .z = 0 },
        .direction = Vec3{ .x = 0, .y = 1, .z = 0 },
    }) == null);
}
