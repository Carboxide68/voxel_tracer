const std = @import("std");
const vector = @import("utils/vector.zig");
const Vec3 = vector.Vec3;
const math = std.math;

const Camera = @This();
const DEG_TO_GRAD = math.pi / 180.0;

position: Vec3 = Vec3{ .x = 0, .y = 0, .z = 0 },
view_matrix: [3]Vec3,
fov: [2]f32 = .{ 90, 90 },

pub const Ray = struct {
    origin: Vec3,
    direction: Vec3,
};

pub fn init(pos: Vec3, dir: Vec3, fov: ?[2]f32) Camera {
    const fov_real = if (fov) |f| f else [2]f32{ 90, 90 };
    var self = Camera{
        .position = pos,
        .view_matrix = undefined,
        .fov = fov_real,
    };
    self.updateCameraMatrix(dir);
    return self;
}

pub fn updateCameraMatrix(self: *Camera, dir: Vec3) void {
    const UP = Vec3.fromData(.{ 0, 1, 0 });
    const side = dir.cross(UP);
    const up = side.cross(dir);
    self.view_matrix = .{
        dir,
        up,
        side,
    };
}

///Cast a ray at the location ([-1, 1]) of the screen
pub fn castRay(self: Camera, location: [2]f32) Ray {
    const angle = [2]f32{
        self.fov[0] * location[0] * DEG_TO_GRAD,
        self.fov[1] * location[1] * DEG_TO_GRAD,
    };
    const rel_dir = Vec3{
        .x = math.cos(angle[0]) * math.cos(angle[1]),
        .y = math.sin(angle[1]),
        .z = math.sin(angle[0]) * math.cos(angle[1]),
    };
    const dir = (self.view_matrix[0].sMult(rel_dir.x).add(
        self.view_matrix[1].sMult(rel_dir.y).add(
            self.view_matrix[2].sMult(rel_dir.z),
        ),
    ));
    return .{
        .direction = dir,
        .origin = self.position,
    };
}

pub fn castRayVar(self: Camera, location: [2]f32, variance: f32, rnd: std.rand.Random) Ray {
    const l = rnd.float(f32) * variance;
    const var_angle = rnd.float(f32) * 2 * math.pi;
    const angle = [2]f32{
        self.fov[0] * location[0] * DEG_TO_GRAD + math.cos(var_angle) * l,
        self.fov[1] * location[1] * DEG_TO_GRAD + math.sin(var_angle) * l,
    };
    const rel_dir = Vec3{
        .x = math.cos(angle[0]) * math.cos(angle[1]),
        .y = math.sin(angle[1]),
        .z = math.sin(angle[0]) * math.cos(angle[1]),
    };
    const dir = (self.view_matrix[0].sMult(rel_dir.x).add(
        self.view_matrix[1].sMult(rel_dir.y).add(
            self.view_matrix[2].sMult(rel_dir.z),
        ),
    ));
    return .{
        .direction = dir,
        .origin = self.position,
    };
}
