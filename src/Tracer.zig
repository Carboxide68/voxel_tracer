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

const is_debug = @import("builtin").mode == .Debug;

pub const Box = extern struct {
    pos: Vec3,
    size: Vec3, //Shouldn't ever contain negative values

    pub fn toAABB(self: Box) AABB {
        return .{
            .min = self.pos.sub(self.size),
            .max = self.pos.add(self.size),
        };
    }
};

pub const AABB = extern struct {
    min: Vec3,
    max: Vec3,

    pub fn toBox(self: AABB) Box {
        const size = (self.max.simd() - self.min.simd()) / @splat(3, @as(f32, 2));
        const center = (self.max.simd() + self.min.simd()) / @splat(3, @as(f32, 2));
        return .{ .pos = center, .size = size };
    }
};

pub const SurfaceHit = struct {
    position: Vec3,
    normal: Vec3,
};

pub const Hit = struct {
    position: Vec3,
    normal: Vec3,
    hit_index: u32,
};

pub const Timings = struct {
    pub var trace_scene: i128 = 0;
};

var _rand_proto = std.rand.DefaultPrng.init(11);
const rnd = _rand_proto.random();

a: std.mem.Allocator,
f_a: std.heap.ArenaAllocator,
rand: std.rand.DefaultPrng,

boxes: std.ArrayList(Box),
colors: std.ArrayList(Vec3),

camera: Camera,

vao: VertexArray,
vertex_buffer: Buffer,
image_buffer: Buffer,
drawer: Shader,

frame: [2]u32,
pixels: []Vec4,
samples: u32,
variance: f32,
clear_color: Vec4,

pub fn init(a: std.mem.Allocator) !Tracer {
    const seed: u64 = if (is_debug) 7 else @intCast(u64, std.time.milliTimestamp());
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
    self.f_a = std.heap.ArenaAllocator.init(self.a);
    self.rand = std.rand.DefaultPrng.init(seed);
    self.clear_color = Vec4.fromData(.{ 0.5, 0.5, 0, 0 });
    self.samples = 0;
    self.variance = 0.001;
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
    self.a.free(self.pixels);
    self.f_a.deinit();
}

pub fn addCube(self: *Tracer, pos: Vec3, s: FPrec, color: Vec3) void {
    self.boxes.append(Box{
        .pos = pos,
        .size = Vec3.fromSimd(@splat(3, s)),
    }) catch |err| log.err("Failed to add to array! Error: {}", .{err});
    self.colors.append(color) catch |err| log.err("Failed to add to array! Error: {}", .{err});
}

pub fn addBox(self: *Tracer, box: Box, color: Vec3) void {
    self.boxes.append(box) catch |err| log.err("Failed to add to array! Error: {}", .{err});
    self.colors.append(color) catch |err| log.err("Failed to add to array! Error: {}", .{err});
}

pub fn traceScene(self: *Tracer) void {
    const fun_begin = std.time.nanoTimestamp();
    self.samples += 1;

    const w = @intToFloat(f32, self.frame[0]);
    const h = @intToFloat(f32, self.frame[1]);
    for (0..self.frame[1]) |i| {
        for (self.pixels[self.frame[0] * i .. self.frame[0] * (i + 1)], 0..) |*pixel, k| {
            const rel_pos = [2]f32{
                2 * @intToFloat(f32, k) / w - 1,
                2 * @intToFloat(f32, i) / h - 1,
            };
            const hit = self.trace(self.camera.castRayVar(rel_pos, self.variance, self.rand.random())) catch |err| {
                if (!is_debug) {
                    unreachable;
                }
                log.err("Failed to allocate memory in arena buffer!\nErr: {}", .{err});
                continue;
            };
            if (hit.len != 0) {
                const color = self.colors.items[hit[0].hit_index];
                _ = color;
                //const true_color = Vec4{ .x = color.x, .y = color.y, .z = color.z, .w = 1 };
                const true_color = Vec4{ .x = @fabs(hit[0].normal.x), .y = @fabs(hit[0].normal.y), .z = @fabs(hit[0].normal.z), .w = 1 };
                log.info("Color: {}", .{true_color});
                if (self.samples == 1) {
                    pixel.* = true_color;
                } else {
                    pixel.* = pixel.add(true_color);
                }
            } else {
                if (self.samples == 1) {
                    pixel.* = self.clear_color;
                } else {
                    pixel.* = pixel.add(self.clear_color);
                }
            }
        }
    }
    Timings.trace_scene = std.time.nanoTimestamp() - fun_begin;

    log.info("Trace Scene took {}ms!", .{@divFloor(Timings.trace_scene, 1000)});
    self.image_buffer.subData(
        0,
        @sizeOf(Vec4) * self.frame[0] * self.frame[1],
        self.pixels,
    ) catch |err| {
        log.err("Failed to upload image to GPU buffer! Error: {}", .{err});
    };
    if (!self.f_a.reset(.retain_capacity)) {
        log.warn("Failed to allocate with retained capacity! Falling back on freeing all.", .{});
        _ = self.f_a.reset(.free_all);
    }
}

pub fn clearImage(self: *Tracer) void {
    self.samples = 0;
    for (self.pixels) |*pixel| pixel.* = self.clear_color;
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
    self.drawer.uniform(
        if (self.samples == 0) 1 else self.samples,
        "u_sample_count",
    );
    self.image_buffer.bindAll(.shader_storage, 0) catch unreachable;
    self.vao.drawArrays(.triangles, 0, 6);
}

pub inline fn aabbHit(n_inv: Vec3, ray_origin: Vec3, aabb: AABB) bool {
    const t1 = (aabb.min.simd() - ray_origin.simd()) * n_inv.simd();
    const t2 = (aabb.max.simd() - ray_origin.simd()) * n_inv.simd();
    const min = @min(t1, t2);
    const max = @max(t1, t2);
    const tmin = @reduce(.Max, min);
    const tmax = @reduce(.Min, max);
    return tmin < tmax and tmax >= 0;
}

pub fn boxHit(ray_d: Vec3, n_inv: Vec3, pos: Vec3, box: Box) ?SurfaceHit {
    const m = n_inv.simd();
    const ro = pos.simd() - box.pos.simd();
    const n = ro * m;
    const k = box.size.simd() * @fabs(m);
    const t1 = -k - n;
    const t2 = k - n;
    const tn = @reduce(.Max, t1);
    const tf = @reduce(.Min, t2);
    log.debug("tN: {}, tF: {}", .{ tn, tf });
    if (tn > tf or tf < 0) return null;
    var hit_pos: Vec3 = undefined;
    const norm = blk: {
        if (tn > 0) {
            const tnv = @splat(3, tn);
            hit_pos = ray_d.sMult(tn);
            break :blk -std.math.sign(ray_d.simd()) * @select(
                f32,
                tnv < t1,
                @splat(3, @as(f32, 1)),
                @splat(3, @as(f32, 0)),
            );
        } else {
            const tfv = @splat(3, tf);
            hit_pos = ray_d.sMult(tf);
            break :blk -std.math.sign(ray_d.simd()) * @select(
                f32,
                t2 < tfv,
                @splat(3, @as(f32, 1)),
                @splat(3, @as(f32, 0)),
            );
        }
    };
    return SurfaceHit{
        .position = hit_pos,
        .normal = Vec3.fromSimd(norm),
    };
}

pub fn trace(self: *Tracer, ray: Ray) ![]Hit {
    const a = self.f_a.allocator();
    const pos = ray.origin;
    const n_inv = Vec3.fromSimd(@splat(3, @as(f32, 1)) / ray.direction.simd());
    var hits = std.ArrayList(Hit).init(a);
    for (self.boxes.items, 0..) |box, i| {
        const hit = boxHit(ray.direction, n_inv, pos, box) orelse continue;
        try hits.append(Hit{
            .position = hit.position,
            .normal = hit.normal,
            .hit_index = @intCast(u32, i),
        });
    }
    return hits.toOwnedSlice() catch |err| blk: {
        log.debug("Failed to convert to owned slice! Err: {}", .{err});
        break :blk &.{};
    };
}

//fn traceX(comptime count: comptime_int, self: Tracer, origin: Vec3, n_inv: Vec3, direction: Vec3, boxes: []Box) []Hit {
//    const a = self.f_a.allocator();
//    const bs = @bitCast(@Vector(count * 6, f32), @ptrCast(*[count * 6]f32, boxes.ptr.*).*);
//    const n_inv_many = n_inv.simd() ** count;
//    const origin_many = origin.simd() ** count;
//    const t = (bs - origin_many) * n_inv_many;
//    const mask: @Vector(count * 3, i32) = comptime blk: {
//        var mask_bits: [count * 3]i32 = undefined;
//        inline for (0..count) |i| {
//            const k = i * 6;
//            mask_bits[i * 3 + 0] = k;
//            mask_bits[i * 3 + 1] = k + 1;
//            mask_bits[i * 3 + 2] = k + 2;
//        }
//        break :blk mask_bits;
//    };
//    const t1 = @shuffle(f32, t, undefined, mask);
//    const t2 = @shuffle(f32, t, undefined, mask + @splat(count * 3, @as(i3, 3)));
//    const min = @min(t1, t2);
//    const max = @max(t1, t2);
//    var hits = std.ArrayList(Hit).init(a);
//    for (0..count) |i| {
//        const tmin = @reduce(.Max, min[i * 3 .. (i + 1) * 3]);
//        const tmax = @reduce(.Min, max[i * 3 .. (i + 1) * 3]);
//        if (tmin < tmax and tmax >= 0) {
//            var hit_pos: Vec3 = undefined;
//            if (tmin < 0) {
//                hit_pos = direction.sMult(tmax);
//            } else {
//                hit_pos = direction.sMult(tmin);
//            }
//            hits.append(Hit{ .hit_index = @intCast(u32, i), .postion = hit_pos });
//        }
//    }
//    return hits.toOwnedSlice() catch |err| blk: {
//        log.err("Failed to convert to owned slice! Err: {}", .{err});
//        break :blk &.{};
//    };
//}

pub fn tester() !void {
    if (@import("builtin").mode != .Debug) return;

    const box = Box{
        .pos = .{ .x = 0, .y = 0, .z = 1 },
        .size = .{ .x = 0.1, .y = 0.1, .z = 0.1 },
    };
    {
        const ray = Ray{
            .origin = Vec3{ .x = 1, .y = 0, .z = 1 },
            .direction = Vec3{ .x = -1, .y = 0, .z = 0 },
        };
        const n_inv = Vec3.fromSimd(@splat(3, @as(f32, 1)) / ray.direction.simd());
        try std.testing.expect(
            Tracer.boxHit(ray.direction, n_inv, ray.origin, box) != null,
        );
    }
    {
        const ray = Ray{
            .origin = Vec3{ .x = 0, .y = 0, .z = 0 },
            .direction = Vec3{ .x = 0, .y = 0, .z = 1 },
        };
        const n_inv = Vec3.fromSimd(@splat(3, @as(f32, 1)) / ray.direction.simd());
        try std.testing.expect(
            Tracer.boxHit(ray.direction, n_inv, ray.origin, box) != null,
        );
    }
    {
        const ray = Ray{
            .origin = Vec3{ .x = 0, .y = 0, .z = 2 },
            .direction = Vec3{ .x = 0, .y = 0, .z = -1 },
        };
        const n_inv = Vec3.fromSimd(@splat(3, @as(f32, 1)) / ray.direction.simd());
        try std.testing.expect(
            Tracer.boxHit(ray.direction, n_inv, ray.origin, box) != null,
        );
    }
    {
        const ray = Ray{
            .origin = Vec3{ .x = 0, .y = 0, .z = 0 },
            .direction = Vec3{ .x = 0, .y = 1, .z = 0 },
        };
        const n_inv = Vec3.fromSimd(@splat(3, @as(f32, 1)) / ray.direction.simd());
        try std.testing.expect(
            Tracer.boxHit(ray.direction, n_inv, ray.origin, box) == null,
        );
    }
    {
        const ray = Ray{
            .origin = Vec3{ .x = 0, .y = 0, .z = 0 },
            .direction = Vec3{ .x = 0, .y = 0.7, .z = 0.7 },
        };
        const n_inv = Vec3.fromSimd(@splat(3, @as(f32, 1)) / ray.direction.simd());
        try std.testing.expect(
            Tracer.boxHit(ray.direction, n_inv, ray.origin, box) == null,
        );
    }
    log.debug("Tests passed!", .{});
}
