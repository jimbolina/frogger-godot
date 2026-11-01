shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform vec2 projection_scale = vec2(1.0);
uniform float depth_bias = 0.0;
uniform float halo_strength = 2.0;
uniform float falloff = 3.0;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (depth_bias != 0.0) {
		vec4 eye = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		vec4 nearer = PROJECTION_MATRIX * vec4(eye.xy, eye.z + depth_bias / 256.0, 1.0);
		if (nearer.w > 0.0) {
			POSITION.z = nearer.z / nearer.w * POSITION.w;
		}
	}
	POSITION.xy *= projection_scale;
}

vec3 to_linear(vec3 stored) {
	return mix(stored / 12.92, pow((stored + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), stored));
}

void fragment() {
	float radial = pow(clamp(1.0 - length(UV * 2.0 - 1.0), 0.0, 1.0), falloff);
	ALBEDO = to_linear(min(COLOR.rgb * 2.0, vec3(1.0))) * radial * halo_strength;
	ALPHA = 1.0;
}
