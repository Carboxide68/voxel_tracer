const std = @import("std");
const vector = @import("utils/vector.zig");
const Vec3 = vector.Vec3;
const math = std.math;

const Camera = @This();
const DEG_TO_GRAD = math.pi / 180.0;

position: Vec3 = Vec3{ .x = 0, .y = 0, .z = 0 },
fwd: Vec3 = .{ .x = 0, .y = 0, .z = 1 },
up: Vec3 = .{ .x = 0, .y = 1, .z = 0 },
side: Vec3 = .{ .x = -1, .y = 0, .z = 0 },

dof: f32 = 0.3,

pub const Ray = struct {
    origin: Vec3,
    direction: Vec3,
};

pub fn init(pos: Vec3, dir: Vec3, dof: ?f32) Camera {
    const dof_real = if (dof) |f| f else 0.3;
    var self = Camera{
        .position = pos,
        .dof = dof_real,
    };
    self.updateCameraMatrix(dir);
    return self;
}

pub fn lookAt(self: *Camera, point: Vec3) void {
    self.updateCameraMatrix(point.sub(self.position).normalize());
}

///`dir` should be normalized
pub fn updateCameraMatrix(self: *Camera, dir: Vec3) void {
    const UP = Vec3.fromData(.{ 0, 1, 0 });
    self.side = dir.cross(UP).normalize();
    self.up = self.side.cross(dir);
    self.fwd = dir;
}

///Cast a ray at the location ([-1, 1]) of the screen
pub fn castRay(self: Camera, location: [2]f32) Ray {
    const l = [2]f32{ location[0] / 2, location[1] / 2 };
    const rel_dir = (Vec3{
        .x = self.dof,
        .y = l[1],
        .z = l[0],
    }).normalize();
    const dir = Vec3.fromSimd(
        self.fwd.sMult(rel_dir.x).simd() + self.up.sMult(rel_dir.y).simd() + self.side.sMult(rel_dir.z).simd(),
    );
    return .{
        .direction = dir,
        .origin = self.position,
    };
}

pub fn varyRay(dir: Vec3, variance: f32, rnd: std.rand.Random) Vec3 {
    var r: Vec3 = undefined;
    while (true) {
        r.x = rnd.float(f32);
        r.y = rnd.float(f32);
        r.z = rnd.float(f32);
        if (r.length2() <= 1) break;
    }
    r = r.normalize();
    return dir.add(r.sMult(variance)).normalize();
}

pub fn castRayVar(self: Camera, location: [2]f32, variance: f32, rnd: std.rand.Random) Ray {
    const ray = self.castRay(location);
    return .{
        .direction = varyRay(ray.direction, variance, rnd),
        .origin = ray.origin,
    };
}
