shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform sampler2D image : filter_nearest, repeat_disable;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);

uniform vec2 projection_scale = vec2(1.0);
uniform float depth_bias = 0.0;
uniform bool source_lighting = false;
uniform vec3 source_ambient = vec3(4096.0);
uniform vec3 source_direction0 = vec3(0.0);
uniform vec3 source_direction1 = vec3(0.0);
uniform vec3 source_direction2 = vec3(0.0);
uniform vec3 source_colour0 = vec3(0.0);
uniform vec3 source_colour1 = vec3(0.0);
uniform vec3 source_colour2 = vec3(0.0);
uniform bool cel_enabled = false;
uniform sampler2D cel_texture : filter_nearest, repeat_disable;
uniform int cel_vertex_count = 0;
uniform ivec2 cel_pair = ivec2(0);
uniform float cel_weight = 1.0;
vec3 cel_value(int cel, int vertex_id, int component) {
	int index = (cel * cel_vertex_count + vertex_id) * 2 + component;
	int width = textureSize(cel_texture, 0).x;
	return texelFetch(cel_texture, ivec2(index % width, index / width), 0).xyz;
}
void vertex() {
	if (cel_enabled) {
		VERTEX = mix(cel_value(cel_pair.x, VERTEX_ID, 0), cel_value(cel_pair.y, VERTEX_ID, 0), cel_weight);
		vec3 normal = mix(cel_value(cel_pair.x, VERTEX_ID, 1), cel_value(cel_pair.y, VERTEX_ID, 1), cel_weight);
		NORMAL = length(normal) > 0.000001 ? normalize(normal) : vec3(0.0);
	}
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (depth_bias != 0.0) {
		vec4 eye = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		vec4 nearer = PROJECTION_MATRIX * vec4(eye.xy, eye.z + depth_bias / 256.0, 1.0);
		if (nearer.w > 0.0) {
			POSITION.z = nearer.z / nearer.w * POSITION.w;
		}
	}
	POSITION.xy *= projection_scale;
	if (source_lighting) {
		vec3 normal = mat3(MODEL_MATRIX) * NORMAL;
		vec3 light = source_ambient;
		light += source_colour0 * max(0.0, dot(source_direction0, normal));
		light += source_colour1 * max(0.0, dot(source_direction1, normal));
		light += source_colour2 * max(0.0, dot(source_direction2, normal));
		COLOR.rgb = clamp(floor(COLOR.rgb * 255.0 * light / 4096.0), vec3(0.0), vec3(255.0)) / 255.0;
	}
}

vec3 through_renderer(vec3 wanted) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 linear = pow((wanted + 0.055) / 1.055, vec3(2.4));
	vec3 a = wanted;
	for (int i = 0; i < 4; i++) {
		vec3 value = a * (a * (a * 0.305306011 + 0.682171111) + 0.012522878) - linear;
		vec3 slope = a * (a * 0.915918033 + 1.364342222) + 0.012522878;
		a -= value / slope;
	}
	return max(a, vec3(0.0));
#else
	return mix(wanted / 12.92, pow((wanted + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), wanted));
#endif
}

void fragment() {
	vec4 texel = texture(image, UV * uv_scale + uv_offset);
	if (texel.a < 0.5) {
		discard;
	}
	vec3 shown = texel.rgb * min(COLOR.rgb * 2.0, vec3(1.0));
	ALBEDO = through_renderer(clamp(shown, vec3(0.0), vec3(1.0)));
	ALPHA = 0.5;
}
