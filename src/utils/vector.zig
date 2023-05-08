const std = @import("std");

pub const Vec2 = Vec2T(f32);
pub const Vec3 = Vec3T(f32);
pub const Vec4 = Vec4T(f32);

pub fn vecProto(comptime T: type, comptime S: type, comptime dims: comptime_int) type {
    return struct {
        const DataType = [dims]S;
        const SimdType = @Vector(dims, S);

        pub inline fn init(v: S) T {
            return fromData([_]S{v} ** dims);
        }

        pub inline fn simd(this: T) SimdType {
            return @as(SimdType, @bitCast(DataType, this));
        }

        pub inline fn data(this: T) DataType {
            return @bitCast(DataType, this);
        }

        pub inline fn fromData(d: DataType) T {
            return @bitCast(T, d);
        }

        pub inline fn fromSimd(val: @Vector(dims, S)) T {
            return @bitCast(T, @as(DataType, val));
        }

        pub inline fn add(this: T, other: T) T {
            return fromSimd(simd(this) + simd(other));
        }

        pub inline fn sAdd(this: T, other: S) T {
            return fromSimd(simd(this) + @splat(dims, other));
        }

        pub inline fn mult(this: T, other: T) T {
            return fromSimd(simd(this) * simd(other));
        }

        pub inline fn sMult(this: T, other: S) T {
            return fromSimd(simd(this) * @splat(dims, other));
        }

        pub inline fn sub(this: T, other: T) T {
            return fromSimd(simd(this) - simd(other));
        }

        pub inline fn sSub(this: T, other: S) T {
            return fromSimd(simd(this) - @splat(dims, other));
        }

        pub inline fn dot(this: T, other: T) S {
            return @reduce(.Add, simd(this) * simd(other));
        }

        pub inline fn length(this: T) S {
            return @sqrt(length2(this));
        }

        pub inline fn length2(this: T) S {
            return dot(this, this);
        }
    };
}

pub fn Vec2T(comptime T: type) type {
    return extern struct {
        const proto = vecProto(@This(), T, 2);
        pub usingnamespace proto;

        x: T,
        y: T,
    };
}

pub fn Vec3T(comptime T: type) type {
    return extern struct {
        const proto = vecProto(@This(), T, 3);
        pub usingnamespace proto;

        x: T,
        y: T,
        z: T,

        pub fn cross(this: @This(), other: @This()) @This() {
            return .{
                .x = this.y * other.z - this.z * other.y,
                .y = this.z * other.x - this.x * other.z,
                .z = this.x * other.y - this.y * other.x,
            };
        }
    };
}

pub fn Vec4T(comptime T: type) type {
    return extern struct {
        const proto = vecProto(@This(), T, 4);
        pub usingnamespace proto;

        x: T,
        y: T,
        z: T,
        w: T,
    };
}

test "Proto Test" {
    const v = Vec2T(f32){ .x = 10, .y = 3 };
    const o = Vec2T(f32){ .x = 7, .y = 8 };
    std.debug.print("Add: {}\nSub: {}\nMult: {}\nDot: {}\nsMult: {}\n", .{ v.add(o), v.sub(o), v.mult(o), v.dot(o), v.sMult(2) });
}
