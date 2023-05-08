pub usingnamespace @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cDefine("CIMGUI_USE_GLFW", "1");
    @cDefine("CIMGUI_USE_OPENGL3", "1");
    @cInclude("cimgui.h");
    @cInclude("generator/output/cimgui_impl.h");
    @cUndef("CIMGUI_USE_GLFW");
    @cUndef("CIMGUI_USE_OPENGL3");
    @cUndef("CIMGUI_DEFINE_ENUMS_AND_STRUCTS");

    @cInclude("GL/glew.h");
});
