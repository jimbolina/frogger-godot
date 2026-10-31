shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D image_nearest : source_color, filter_nearest, repeat_disable;
uniform sampler2D image_linear : source_color, filter_linear_mipmap, repeat_disable;
uniform bool linear_filter = false;
uniform vec2 pixel_scale = vec2(1.0);
uniform vec2 texel_inset = vec2(0.0);
uniform bool missing_image = false;
uniform vec2 projection_scale = vec2(1.0);
uniform float far_layer = 0.0;

vec3 to_linear(vec3 stored) {
	return mix(stored / 12.92, pow((stored + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), stored));
}

void vertex() {
	vec2 pixel = mod(UV, vec2(256.0));
	pixel.y += UV2.x * 258.0 + 1.0;
	UV = pixel * pixel_scale;
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = POSITION.w * (CLIP_SPACE_FAR + (far_layer + 1.0) * 0.00001);
	POSITION.xy *= projection_scale;
}

void fragment() {
	vec4 texel;
	if (linear_filter) {
		texel = texture(image_linear, UV - texel_inset);
	} else {
		texel = texture(image_nearest, UV);
	}
	if (texel.a < 0.5 && !missing_image) {
		discard;
	}
	vec3 shown = texel.rgb * to_linear(min(COLOR.rgb * 2.0, vec3(1.0)));
	if (missing_image) {
		shown = vec3(1.0, 0.0, 1.0);
	}
	ALPHA = 1.0;
	ALBEDO = shown;
}
