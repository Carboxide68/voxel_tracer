const std = @import("std");
const log = std.log.scoped(.coxel);
const c = @import("c.zig");
const glfw = @import("glfw");
const Window = glfw.Window;
const gl = @import("gl.zig");

const glsl_version = "#version 130";
const Renderer = @This();
const RenderError = error{
    InitializeFailed,
};

pub var ig_context: *c.struct_ImGuiContext = undefined;

window: Window,

pub fn init() !Renderer {
    gl.initGlfw() catch {
        log.err("Failed to init glfw!", .{});
        return RenderError.InitializeFailed;
    };

    ig_context = c.igCreateContext(null);

    var self: Renderer = undefined;
    self.window = Window.create(640, 480, "Hello World", null, null, .{
        .context_version_major = 4,
        .context_version_minor = 6,
        .opengl_profile = .opengl_core_profile,
    }) orelse {
        log.err("Failed to create the window!", .{});
        return RenderError.InitializeFailed;
    };

    gl.initGlew(&self.window) catch {
        log.err("Failed to initialize Glew!", .{});
        return RenderError.InitializeFailed;
    };

    if (!c.ImGui_ImplGlfw_InitForOpenGL(
        @ptrCast(*c.GLFWwindow, self.window.handle),
        true,
    )) {
        log.err("Could not initialize ImGui!", .{});
        std.debug.panic("", .{});
        return RenderError.InitializeFailed;
    }

    if (!c.ImGui_ImplOpenGL3_Init(glsl_version)) {
        log.err("Could not initialize ImGui!", .{});
        return RenderError.InitializeFailed;
    }

    c.ImGui_ImplOpenGL3_NewFrame();
    c.ImGui_ImplGlfw_NewFrame();
    c.igNewFrame();
    self.clear_color(.{ 0.5, 0.4, 0.8, 1.0 });
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
    return self;
}

pub fn deinit(self: *Renderer) void {
    self.window.destroy();
    c.ImGui_ImplOpenGL3_Shutdown();
    c.ImGui_ImplGlfw_Shutdown();
    c.igDestroyContext(ig_context);
    gl.deinit();
}

pub fn clear_color(_: Renderer, color: [4]f32) void {
    c.glClearColor(color[0], color[1], color[2], color[3]);
}

pub fn draw_frame(self: *Renderer) bool {
    //End
    c.igRender();
    c.ImGui_ImplOpenGL3_RenderDrawData(c.igGetDrawData());
    self.window.swapBuffers();

    //Start
    glfw.pollEvents();
    c.ImGui_ImplOpenGL3_NewFrame();
    c.ImGui_ImplGlfw_NewFrame();
    c.igNewFrame();
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
    c.igShowDemoWindow(null);
    return !self.window.shouldClose();
}

pub fn button(text: [:0]const u8) bool {
    var text_size: c.ImVec2 = undefined;
    if (text.len == 0) {
        text_size = c.ImVec2{ .x = 0, .y = 0 };
    } else {
        c.igCalcTextSize(&text_size, text.ptr, &text[text.len], true, 1000.0);
    }
    text_size.x += 8;
    text_size.y += 8;
    return c.igButton(text, text_size);
}
