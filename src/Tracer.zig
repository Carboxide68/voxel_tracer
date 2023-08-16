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
        const size = (self.max.simd() - self.min.simd()) /
            @as(@Vector(3, f32), @splat(2));
        const center = (self.max.simd() + self.min.simd()) /
            @as(@Vector(3, f32), @splat(2));
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

pub const Material = struct {
    color: Vec3,
    scatter_variance: f32 = 0.01,
};

var _rand_proto = std.rand.DefaultPrng.init(11);
const rnd = _rand_proto.random();

a: std.mem.Allocator,
f_a: std.heap.ArenaAllocator,
rand: std.rand.DefaultPrng,

boxes: std.ArrayList(Box),
materials: std.ArrayList(Material),

camera: Camera,

vao: VertexArray,
vertex_buffer: Buffer,
image_buffer: Buffer,
drawer: Shader,

frame: [2]u32,
pixels: []Vec4,
samples: u32,
variance: f32,
clear_color: Vec3,

max_depth: u32,

pub fn init(a: std.mem.Allocator) !Tracer {
    const seed: u64 = if (is_debug) 7 else @as(u64, @intCast(std.time.milliTimestamp()));
    var self: Tracer = undefined;
    self.boxes = std.ArrayList(Box).init(a);
    self.materials = std.ArrayList(Material).init(a);
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
    self.clear_color = Vec3{ .d = .{ 1, 1, 1 } };
    self.samples = 0;
    self.variance = 0.001;
    self.camera = Camera.init(
        Vec3{ .d = .{ 0, 0, 0 } },
        Vec3{ .d = .{ 0, 0, 1 } },
        null,
    );
    self.max_depth = 1;
    return self;
}

pub fn destroy(self: *Tracer) void {
    self.boxes.deinit();
    self.materials.deinit();
    self.drawer.destroy();
    self.vao.destroy();
    self.vertex_buffer.destroy();
    self.image_buffer.destroy();
    self.a.free(self.pixels);
    self.f_a.deinit();
}

pub fn resize(self: *Tracer, h: u32, w: u32) void {
    self.clearImage();
    self.pixels = self.a.realloc(self.pixels, h * w) catch |err| {
        log.err("Failed to reallocate screen buffer! Err: {}", .{err});
        return;
    };
    self.frame[0] = h;
    self.frame[1] = w;
    self.image_buffer.realloc(h * w * 16, .dynamic_draw);
}

pub fn addCube(self: *Tracer, pos: Vec3, s: FPrec, material: Material) void {
    self.boxes.append(Box{
        .pos = pos,
        .size = Vec3.fromSimd(@splat(s)),
    }) catch |err| log.err("Failed to add to array! Error: {}", .{err});
    self.materials.append(material) catch |err| log.err("Failed to add to array! Error: {}", .{err});
}

pub fn addBox(self: *Tracer, box: Box, color: Vec3) void {
    self.boxes.append(box) catch |err| log.err("Failed to add to array! Error: {}", .{err});
    self.colors.append(color) catch |err| log.err("Failed to add to array! Error: {}", .{err});
}

fn colorEval(self: Tracer, hits: []Hit, rays: []Ray) Vec4 {
    const FALLOFF = 0.5;
    const y_val = std.math.pow(f32, rays[rays.len - 1].direction.y(), 2);
    var color = Vec3.init(1).sMult(1 - y_val).add((Vec3{ .d = .{ 0.5, 0.5, 1 } }).sMult(y_val));
    for (0..hits.len) |i| {
        const hit = hits[hits.len - i - 1];
        const mat = self.materials.items[hit.hit_index];
        color = color.add(mat.color);
        color = color.sMult(FALLOFF);
    }
    return Vec4{ .d = .{ color.d[0], color.d[1], color.d[2], 1 } };
}

pub fn traceScene(self: *Tracer) void {
    const fun_begin = std.time.nanoTimestamp();
    self.samples += 1;

    const w = @as(f32, @floatFromInt(self.frame[0]));
    const h = @as(f32, @floatFromInt(self.frame[1]));
    for (0..self.frame[1]) |i| {
        for (self.pixels[self.frame[0] * i .. self.frame[0] * (i + 1)], 0..) |*pixel, k| {
            var bounces = std.ArrayList(Hit).init(self.f_a.allocator());
            var rays = std.ArrayList(Ray).init(self.f_a.allocator());
            const min = @min(w, h);
            const rel_pos = [2]f32{
                2 * @as(f32, @floatFromInt(k)) / min - 1,
                2 * @as(f32, @floatFromInt(i)) / min - 1,
            };
            var r = self.camera.castRayVar(rel_pos, self.variance, self.rand.random());
            rays.append(r) catch unreachable;

            for (0..self.max_depth) |_| {
                var hits = self.trace(r);
                if (hits.len == 0) break;
                const hit = blk: {
                    var closest = std.math.inf(f32);
                    var index: u32 = 0;
                    for (hits, 0..) |hit, j| {
                        const new_length = hit.position.sub(self.camera.position).length2();
                        if (new_length < closest) {
                            index = @as(u32, @intCast(j));
                            closest = new_length;
                        }
                    }
                    break :blk hits[index];
                };
                bounces.append(hit) catch |err| {
                    if (!is_debug) {
                        unreachable;
                    }
                    log.err("Failed to allocate memory in arena buffer!\nErr: {}", .{err});
                    return;
                };

                var new_dir = hit.normal.sMult(-2 * r.direction.normalize().dot(hit.normal));
                const mat = self.materials.items[hit.hit_index];
                new_dir = r.direction.add(new_dir);
                new_dir = Camera.varyRay(
                    new_dir,
                    mat.scatter_variance,
                    self.rand.random(),
                );
                r = Ray{
                    .origin = hit.position.add(new_dir.sMult(0.005)),
                    .direction = new_dir,
                };
                rays.append(r) catch unreachable;
            }
            pixel.* = pixel.add(self.colorEval(bounces.items, rays.items));
            bounces.deinit();
            rays.deinit();
        }
    }
    Timings.trace_scene = std.time.nanoTimestamp() - fun_begin;

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
    for (self.pixels) |*pixel| pixel.* = Vec4.init(0);
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

pub inline fn hitsAABB(n_inv: Vec3, ray_origin: Vec3, aabb: AABB) bool {
    const t1 = (aabb.min.simd() - ray_origin.simd()) * n_inv.simd();
    const t2 = (aabb.max.simd() - ray_origin.simd()) * n_inv.simd();
    const min = @min(t1, t2);
    const max = @max(t1, t2);
    const tmin = @reduce(.Max, min);
    const tmax = @reduce(.Min, max);
    return tmin < tmax and tmax >= 0;
}

pub fn boxHit(ray_d: Vec3, n_inv: Vec3, pos: Vec3, box: Box) ?SurfaceHit {
    const ro = pos.simd() - box.pos.simd();
    const m = n_inv.simd();
    const n = ro * m;
    const k = box.size.simd() * @fabs(m);
    const t1 = -k - n;
    const t2 = k - n;
    const tn = @reduce(.Max, t1);
    const tf = @reduce(.Min, t2);
    if (tn > tf or tf < 0) return null;
    var hit_pos: Vec3 = undefined;
    const norm = blk: {
        if (tn > 0) {
            hit_pos = ray_d.sMult(tn);
            const tnv: @Vector(3, f32) = @splat(tn);
            break :blk -std.math.sign(ray_d.simd()) * @select(
                f32,
                t1 < tnv,
                @as(@Vector(3, f32), @splat(0)),
                @as(@Vector(3, f32), @splat(1)),
            );
        } else {
            hit_pos = ray_d.sMult(tf);
            const tfv: @Vector(3, f32) = @splat(tf);
            break :blk -std.math.sign(ray_d.simd()) * @select(
                f32,
                tfv < t2,
                @as(@Vector(3, f32), @splat(0)),
                @as(@Vector(3, f32), @splat(1)),
            );
        }
    };
    return SurfaceHit{
        .position = hit_pos.add(pos),
        .normal = Vec3.fromSimd(norm),
    };
}

pub fn trace(self: *Tracer, ray: Ray) []Hit {
    const a = self.f_a.allocator();
    const pos = ray.origin;
    const n_inv = Vec3.fromSimd(@as(@Vector(3, f32), @splat(1)) / ray.direction.simd());
    var hits = std.ArrayList(Hit).init(a);
    for (self.boxes.items, 0..) |box, i| {
        const hit = boxHit(ray.direction, n_inv, pos, box) orelse continue;
        hits.append(Hit{
            .position = hit.position,
            .normal = hit.normal,
            .hit_index = @as(u32, @intCast(i)),
        }) catch |err| {
            log.err("Failed to add to buffer in trace! Err: {}", .{err});
            return &.{};
        };
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
        .pos = .{ .d = .{ 0, 0, 1 } },
        .size = .{ .d = .{ 0.1, 0.1, 0.1 } },
    };
    var counter: u32 = 1;
    {
        const ray = Ray{
            .origin = Vec3{ .d = .{ 1, 0, 1 } },
            .direction = Vec3{ .d = .{ -1, 0, 0 } },
        };
        const n_inv = Vec3.fromSimd(@as(@Vector(3, f32), @splat(1)) / ray.direction.simd());
        try std.testing.expect(
            Tracer.boxHit(ray.direction, n_inv, ray.origin, box) != null,
        );
    } // 1
    std.debug.print("Passed test {}!\n", .{counter});
    counter += 1;
    {
        const ray = Ray{
            .origin = Vec3{ .d = .{ 0, 0, 0 } },
            .direction = Vec3{ .d = .{ 0, 0, 1 } },
        };
        const n_inv = Vec3.fromSimd(@as(@Vector(3, f32), @splat(1)) / ray.direction.simd());
        try std.testing.expect(
            Tracer.boxHit(ray.direction, n_inv, ray.origin, box) != null,
        );
    } // 2
    std.debug.print("Passed test {}!\n", .{counter});
    counter += 1;
    {
        const ray = Ray{
            .origin = Vec3{ .d = .{ 0, 0, 2 } },
            .direction = Vec3{ .d = .{ 0, 0, -1 } },
        };
        const n_inv = Vec3.fromSimd(@as(@Vector(3, f32), @splat(1)) / ray.direction.simd());
        try std.testing.expect(
            Tracer.boxHit(ray.direction, n_inv, ray.origin, box) != null,
        );
    } // 3
    std.debug.print("Passed test {}!\n", .{counter});
    counter += 1;
    {
        const ray = Ray{
            .origin = Vec3{ .d = .{ 0, 0, 0 } },
            .direction = Vec3{ .d = .{ 0, 1, 0 } },
        };
        const n_inv = Vec3.fromSimd(@as(@Vector(3, f32), @splat(1)) / ray.direction.simd());
        try std.testing.expect(
            Tracer.boxHit(ray.direction, n_inv, ray.origin, box) == null,
        );
    } // 4
    std.debug.print("Passed test {}!\n", .{counter});
    counter += 1;
    {
        const ray = Ray{
            .origin = Vec3{ .d = .{ 0, 0, 0 } },
            .direction = Vec3{ .d = .{ 0, 0.7, 0.7 } },
        };
        const n_inv = Vec3.fromSimd(@as(@Vector(3, f32), @splat(1)) / ray.direction.simd());
        try std.testing.expect(
            Tracer.boxHit(ray.direction, n_inv, ray.origin, box) == null,
        );
    } // 5
    std.debug.print("Passed test {}!\n", .{counter});
    counter += 1;
    log.debug("Tests passed!", .{});
}
