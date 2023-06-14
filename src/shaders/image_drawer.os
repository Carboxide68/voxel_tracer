@vertex
#version 460 core

layout(location=0) in vec2 in_Pos;

layout(location=0) out vec2 frag_coord;

uniform uint u_x_size;
uniform uint u_y_size;

void main() {
	float smallest = float(min(u_x_size, u_y_size));
	gl_Position = vec4(
		in_Pos.x,
		in_Pos.y,
		1, 1
	);
	frag_coord = in_Pos;
}

@fragment
#version 460 core

layout(location=0) in vec2 frag_coord;

layout(std430, binding=0) restrict readonly buffer text {
	vec4 pixel[];
} buffer_texture;

uniform uint u_x_size;
uniform uint u_y_size;
uniform uint u_sample_count;

out vec4 Color;

void main() {
	uint x_index = uint(mix(0, float(u_x_size), (frag_coord.x + 1)/2));
	uint y_index = uint(mix(0, float(u_y_size), (frag_coord.y + 1)/2));
	Color = sqrt(buffer_texture.pixel[x_index + y_index * u_x_size]/float(u_sample_count));
}

@end
