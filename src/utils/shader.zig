const std = @import("std");
const File = std.fs.File;
const c = @import("../c.zig");
const v = @import("vector.zig");

const Vec2 = v.Vec2;
const Vec3 = v.Vec3;
const Vec4 = v.Vec4;
const Mat2T = v.Mat2T;
const Mat3T = v.Mat3T;
const Mat4T = v.Mat4T;

const VERTEX = "@vertex";
const FRAGMENT = "@fragment";
const GEOMETRY = "@geometry";
const COMPUTE = "@compute";
const END = "@end";

const ShaderError = error{
    BadFormat,
    OutOfBounds,
};

const ProgramPart = struct {
    pub const ProgramType = enum(c.GLuint) {
        none = 0,
        vertex = c.GL_VERTEX_SHADER,
        geometry = c.GL_GEOMETRY_SHADER,
        fragment = c.GL_FRAGMENT_SHADER,
        compute = c.GL_COMPUTE_SHADER,
        end,

        _,

        pub fn t(self: ProgramType) c.GLuint {
            return @intFromEnum(self);
        }
    };

    _handle: u32 = 0,
    program_type: ProgramType = .none,
};

fn biased_strcmp(leading: []const u8, following: []const u8) bool {
    const len = following.len;
    for (leading[0..], 0..) |char, i| {
        if (i >= len) return true;
        if (following[i] != char) return false;
    } else return false;
}

pub const Shader = struct {
    _program_handle: u32,
    a: std.mem.Allocator,

    pub fn destroy(self: Shader) void {
        c.glDeleteProgram(self._program_handle);
    }

    pub fn bind(self: Shader) void {
        c.glUseProgram(self._program_handle);
    }

    pub fn unbind() void {
        c.glUseProgram(0);
    }

    pub fn uniform(self: Shader, value: anytype, name: []const u8) void {
        const T = @TypeOf(value);
        const loc = blk: {
            var modified_name: [:0]u8 = self.a.allocSentinel(u8, name.len, 0) catch unreachable;
            defer self.a.free(modified_name);
            for (name, 0..) |char, i| modified_name[i] = char;
            break :blk c.glGetUniformLocation(self._program_handle, modified_name);
        };

        switch (T) {
            f32 => c.glUniform1fv(loc, 1, &value),
            [2]f32 => c.glUniform2fv(loc, 1, &value),
            [3]f32 => c.glUniform3fv(loc, 1, &value),
            [4]f32 => c.glUniform4fv(loc, 1, &value),
            Vec2 => c.glUniform2fv(loc, 1, &value.dataC()),
            Vec3 => c.glUniform3fv(loc, 1, &value.dataC()),
            Vec4 => c.glUniform4fv(loc, 1, &value.dataC()),

            u32 => c.glUniform1ui(loc, value),
            i32 => c.glUniform1i(loc, value),

            //Mat2T(f32) => c.glUniformMatrix2fv(loc, 1, c.GL_FALSE, &value.data),
            //Mat3T(f32) => c.glUniformMatrix3fv(loc, 1, c.GL_FALSE, &value.data),
            //Mat4T(f32) => c.glUniformMatrix4fv(loc, 1, c.GL_FALSE, &value.data),

            else => {
                @compileLog("Type ", T, " is not supported as uniform!");
                unreachable;
            },
        }
    }

    pub fn initFile(file_path: []const u8, a: std.mem.Allocator) !Shader {
        const file_string = try readFile(file_path, a);
        defer a.free(file_string);

        const handle = c.glCreateProgram();
        var programs: [4]ProgramPart = undefined;
        var head: u64 = 0;
        var program_count: u32 = 0;
        defer {
            for (programs[0..program_count]) |p| c.glDeleteShader(p._handle);
        }

        while (true) {
            const shader_program = try makeProgram(file_string, &head);
            if (shader_program.program_type == .end) break;
            if (shader_program.program_type == .none) break;

            c.glAttachShader(handle, shader_program._handle);
            programs[program_count] = shader_program;
            program_count += 1;

            if (shader_program.program_type == .compute) break;
        }

        if (program_count == 0) return ShaderError.BadFormat;
        c.glLinkProgram(handle);

        var success: c.GLint = undefined;
        c.glGetProgramiv(handle, c.GL_LINK_STATUS, &success);
        if (success != c.GL_TRUE) {
            var log_length: c.GLsizei = 0;
            var log: [2048]u8 = undefined;

            c.glGetProgramInfoLog(handle, 2048, &log_length, @as([*c]u8, @ptrCast(&log)));
            std.debug.print("Error linking file {s}!\n{s}\n", .{ file_path, log[0..@as(usize, @intCast(log_length))] });
        }

        return Shader{ ._program_handle = handle, .a = a };
    }

    fn readFile(file_path: []const u8, a: std.mem.Allocator) ![]u8 {
        const dir = std.fs.cwd();
        var shader_file: File = undefined;

        if (dir.openFile(file_path, .{ .mode = .read_only })) |F| {
            shader_file = F;
        } else |err| {
            std.debug.print("Failed to read file {s}!\n", .{file_path});
            return err;
        }

        const file_stat = try shader_file.stat();
        var shader_file_string = try a.alloc(u8, file_stat.size);
        _ = try shader_file.readAll(shader_file_string);
        shader_file.close();

        return shader_file_string;
    }

    fn makeProgram(whole: []const u8, head: *u64) !ProgramPart {
        var p: ProgramPart = .{};

        for (whole[(head.*)..]) |char| {
            if (char == '@') break;
            head.* += 1;
        } else return ShaderError.BadFormat;

        if (biased_strcmp(whole[(head.*)..], VERTEX)) p.program_type = .vertex;
        if (biased_strcmp(whole[(head.*)..], FRAGMENT)) p.program_type = .fragment;
        if (biased_strcmp(whole[(head.*)..], GEOMETRY)) p.program_type = .geometry;
        if (biased_strcmp(whole[(head.*)..], COMPUTE)) p.program_type = .compute;
        if (biased_strcmp(whole[(head.*)..], END)) {
            p.program_type = .end;
            return p;
        }
        head.* += 1;

        if (p.program_type == .none) return ShaderError.BadFormat;
        for (whole[(head.*)..]) |char| {
            head.* += 1;
            if (char == '\n') break;
        }
        const begin = head.*;

        for (whole[(head.*)..]) |char| {
            if (char == '@') break;
            head.* += 1;
        } else return ShaderError.BadFormat;

        p._handle = c.glCreateShader(p.program_type.t());
        {
            const length: c_int = @as(c_int, @intCast(head.* - begin));
            const tmp = @as([*c]const u8, @ptrCast(&whole[begin]));
            c.glShaderSource(p._handle, 1, &tmp, &length);
            c.glCompileShader(p._handle);
        }

        var success: c.GLint = undefined;
        c.glGetShaderiv(p._handle, c.GL_COMPILE_STATUS, &success);
        if (success != c.GL_TRUE) {
            var log_length: c.GLsizei = 0;
            var log: [2048]u8 = undefined;
            c.glGetShaderInfoLog(p._handle, 2048, &log_length, &log);
            std.debug.print("Error compiling {}! Error:\n{s}\n", .{ p.program_type, log[0..@as(usize, @intCast(log_length))] });
        }

        return p;
    }
};
