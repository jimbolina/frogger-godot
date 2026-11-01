#ifdef TEXTURED
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
#endif

uniform vec2 projection_scale = vec2(1.0);
uniform float depth_bias = 0.0;
uniform bool cel_enabled = false;
uniform sampler2D cel_texture : filter_nearest, repeat_disable;
uniform int cel_vertex_count = 0;
uniform ivec2 cel_pair = ivec2(0);
uniform float cel_weight = 1.0;
global uniform vec3 frogger_model_ambient;
instance uniform vec3 tint_scale = vec3(1.0);
instance uniform vec4 tint_ambient = vec4(0.0);
vec3 cel_value(int cel, int vertex_id, int component) {
	int index = (cel * cel_vertex_count + vertex_id) * 2 + component;
	int width = textureSize(cel_texture, 0).x;
	return texelFetch(cel_texture, ivec2(index % width, index / width), 0).xyz;
}
void vertex() {
	if (cel_enabled) {
		VERTEX = mix(cel_value(cel_pair.x, VERTEX_ID, 0), cel_value(cel_pair.y, VERTEX_ID, 0), cel_weight);
		vec3 normal = mix(cel_value(cel_pair.x, VERTEX_ID, 1), cel_value(cel_pair.y, VERTEX_ID, 1), cel_weight);
		NORMAL = length(normal) > 0.000001 ? normalize(normal) : vec3(0.0, 1.0, 0.0);
	}
	NORMAL = -NORMAL;
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (!IN_SHADOW_PASS) {
		if (depth_bias != 0.0) {
			vec4 eye = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
			vec4 nearer = PROJECTION_MATRIX * vec4(eye.xy, eye.z + depth_bias / 256.0, 1.0);
			if (nearer.w > 0.0) {
				POSITION.z = nearer.z / nearer.w * POSITION.w;
			}
		}
		POSITION.xy *= projection_scale;
	}
}

vec3 to_linear(vec3 stored) {
	return mix(stored / 12.92, pow((stored + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), stored));
}

void fragment() {
#ifdef TEXTURED
	vec4 texel = texture(image, UV * uv_scale + uv_offset);
	if (texel.a < 0.5) {
		discard;
	}
	vec3 albedo = texel.rgb * to_linear(min(COLOR.rgb * 2.0, vec3(1.0)));
#else
	vec3 albedo = to_linear(COLOR.rgb);
#endif
	albedo *= tint_scale;
#ifdef BLEND_ADD_QUARTER
	albedo *= 0.25;
#endif
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	EMISSION = albedo * mix(frogger_model_ambient, tint_ambient.rgb, tint_ambient.a);
#if defined(BLEND_AVERAGE)
	ALPHA = 0.5;
#elif defined(BLEND_ADD) || defined(BLEND_SUBTRACT) || defined(BLEND_ADD_QUARTER)
	ALPHA = 1.0;
#endif
}
