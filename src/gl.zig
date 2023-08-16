const std = @import("std");
const log = std.log.scoped(.coxel);
const c = @import("c.zig");
const glfw = @import("mach-glfw");

fn glfw_error_callback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.debug.print("GLFW error {}: {s}\n", .{ error_code, description });
}

fn framebuffer_callback(window: glfw.Window, width: u32, height: u32) void {
    _ = window;
    const w: i32 = @intCast(width);
    const h: i32 = @intCast(height);

    c.glViewport(0, 0, w, h);
}

fn opengl_error_callback(source: c.GLenum, error_type: c.GLenum, id: c.GLuint, severity: c.GLenum, length: c.GLsizei, message: [*c]const u8, _: ?*const anyopaque) callconv(.C) void {
    const m = message[0..@intCast(length)];
    _ = id;
    _ = source;
    _ = error_type;
    if (severity == c.GL_DEBUG_SEVERITY_HIGH) {
        std.debug.print("OpenGL Error! | Severity: High | {s}\n", .{m});
        @breakpoint();
    }
}

fn glfw_scroll_callback(window: glfw.Window, x: f64, y: f64) void {
    _ = y;
    _ = x;
    _ = window;
}

var should_pan = false;
fn glfw_mouse_callback(window: glfw.Window, x: f64, y: f64) void {
    _ = y;
    _ = x;
    _ = window;
}

fn glfw_key_callback(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
    _ = window;
    _ = key;
    _ = scancode;
    _ = action;
    _ = mods;
}

fn glfw_mouse_button_callback(window: glfw.Window, button: glfw.MouseButton, action: glfw.Action, mods: glfw.Mods) void {
    _ = mods;
    _ = action;
    _ = button;
    _ = window;
}
const GlError = error{Fail};

pub fn initGlfw() !void {
    if (!glfw.init(.{})) {
        return GlError.Fail;
    }
}

pub fn initGlew(window: *glfw.Window) !void {
    glfw.setErrorCallback(glfw_error_callback);
    glfw.makeContextCurrent(window.*);
    window.setFramebufferSizeCallback(framebuffer_callback);
    window.setScrollCallback(glfw_scroll_callback);
    window.setCursorPosCallback(glfw_mouse_callback);
    window.setMouseButtonCallback(glfw_mouse_button_callback);

    glfw.swapInterval(1);

    const err = c.glewInit();
    if (err != c.GLEW_OK) {
        log.err("Error: {s}\n", .{c.glewGetErrorString(err)});
        return GlError.Fail;
    }
}

pub fn deinit() void {
    glfw.terminate();
}
