shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2DArray tiles : source_color, filter_nearest, repeat_disable;
uniform sampler2DArray tiles_linear : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool linear_filter = false;
uniform vec2 tile_padding = vec2(0.0);
uniform vec2 tile_padded_size = vec2(1.0);
uniform vec2 projection_scale = vec2(1.0);
uniform float far_layer = 0.0;
varying flat float tile_layer;

vec3 to_linear(vec3 stored) {
	return mix(stored / 12.92, pow((stored + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), stored));
}

void vertex() {
	UV = (UV + tile_padding) / tile_padded_size;
	tile_layer = CUSTOM0.x;
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = POSITION.w * (CLIP_SPACE_FAR + (far_layer + 1.0) * 0.00001);
	POSITION.xy *= projection_scale;
}

void fragment() {
	vec3 coordinate = vec3(UV, tile_layer);
	vec4 texel;
	if (linear_filter) {
		texel = texture(tiles_linear, coordinate);
	} else {
		texel = texture(tiles, coordinate);
	}
	if (texel.a < 0.5) {
		discard;
	}
	ALPHA = 1.0;
	ALBEDO = texel.rgb * to_linear(min(COLOR.rgb * 2.0, vec3(1.0)));
}
