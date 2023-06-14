const std = @import("std");
const vector = @import("utils/vector.zig");
const Vec3 = vector.Vec3;

pub const Bounce = struct {};

pub const Hittable = struct {
    scatter: ?fn (void, void) void,
};

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

pub const Ray = struct {
    d: Vec3,
    o: Vec3,
};

pub const RayOptm = struct {
    v: Vec3,
    o: Vec3,
    n_d: Vec3,
};

pub const Hit = struct {
    p: Vec3,
    n: Vec3,
};
