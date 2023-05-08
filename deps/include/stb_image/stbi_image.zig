
pub const stbi = @cImport({
    
    @cDefine("STB_IMAGE_IMPLEMENTATION");
    @cInclude("stb_image.h");

});


pub fn load_from_memory(buffer: [*]const u8, len: i32, x: *i32, y: *i32, channels: *i32, desired_channels: i32) u8 {

    return stbi.stbi_load_from_memory(buffer, len, x, y, channels, desired_channels);

}

pub fn load(filename: [:0]const u8, x: *i32, y: *i32, channel: *i32, desired_channels: i32) {

    return stbi.stbi_load(filename, x, y, channel, desired_channels);

}

pub fn STBI_MALLOC = stbi.STBI_MALLOC;
pub fn STBI_FREE = stbi.STBI_FREE;
