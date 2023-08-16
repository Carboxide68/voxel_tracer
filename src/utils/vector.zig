const std = @import("std");

pub const Vec2 = Vec2T(f32);
pub const Vec3 = Vec3T(f32);
pub const Vec4 = Vec4T(f32);

pub fn vecProto(comptime T: type, comptime S: type, comptime dims: comptime_int) type {
    return struct {
        const DataType = [dims]S;
        const SimdType = @Vector(dims, S);

        pub inline fn init(v: S) T {
            return .{ .d = [_]S{v} ** dims };
        }

        pub inline fn simd(this: T) SimdType {
            return @as(SimdType, this.d);
        }

        pub inline fn fromSimd(val: @Vector(dims, S)) T {
            return T{ .d = @as(DataType, val) };
        }

        pub inline fn add(this: T, other: T) T {
            return fromSimd(simd(this) + simd(other));
        }

        pub inline fn sAdd(this: T, other: S) T {
            return fromSimd(simd(this) + @as(SimdType, @splat(other)));
        }

        pub inline fn mult(this: T, other: T) T {
            return fromSimd(simd(this) * simd(other));
        }

        pub inline fn sMult(this: T, other: S) T {
            return fromSimd(simd(this) * @as(SimdType, @splat(other)));
        }

        pub inline fn sub(this: T, other: T) T {
            return fromSimd(simd(this) - simd(other));
        }

        pub inline fn sSub(this: T, other: S) T {
            return fromSimd(simd(this) - @as(SimdType, @splat(other)));
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

        pub inline fn normalize(this: T) T {
            return this.sMult(1 / this.length());
        }

        pub inline fn x(this: T) S {
            return this.d[0];
        }

        pub inline fn y(this: T) if (dims < 2) void else S {
            comptime if (dims < 2) return;
            return this.d[1];
        }

        pub inline fn z(this: T) if (dims < 3) void else S {
            comptime if (dims < 3) return;
            return this.d[2];
        }

        pub inline fn w(this: T) if (dims < 4) void else S {
            comptime if (dims < 4) return;
            return this.d[3];
        }

        pub const r = x;
        pub const g = y;
        pub const b = z;
        pub const a = w;
    };
}

pub fn Vec2T(comptime T: type) type {
    return extern struct {
        const proto = vecProto(@This(), T, 2);
        pub usingnamespace proto;

        d: [2]T,
    };
}

pub fn Vec3T(comptime T: type) type {
    return extern struct {
        const proto = vecProto(@This(), T, 3);
        pub usingnamespace proto;

        d: [3]T,

        pub inline fn cross(this: @This(), other: @This()) @This() {
            const tx = this.x();
            const ty = this.y();
            const tz = this.z();
            const ox = other.x();
            const oy = other.y();
            const oz = other.z();
            return .{ .d = .{
                ty * oz - tz * oy,
                tz * ox - tx * oz,
                tx * oy - ty * ox,
            } };
        }
    };
}

pub fn Vec4T(comptime T: type) type {
    return extern struct {
        const proto = vecProto(@This(), T, 4);
        pub usingnamespace proto;

        d: [4]T,
    };
}

test "Proto Test" {
    const v = Vec2T(f32){ .x = 10, .y = 3 };
    const o = Vec2T(f32){ .x = 7, .y = 8 };
    std.debug.print("Add: {}\nSub: {}\nMult: {}\nDot: {}\nsMult: {}\n", .{ v.add(o), v.sub(o), v.mult(o), v.dot(o), v.sMult(2) });
}
