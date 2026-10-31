uniform sampler2D image_nearest : source_color, filter_nearest, repeat_enable;
uniform sampler2D image_linear : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool textured = false;
uniform bool linear_filter = false;
uniform vec2 image_origin = vec2(0.0);
uniform vec2 image_padding = vec2(0.0);
uniform vec2 image_padded_size = vec2(1.0);
uniform float vertex_tint = 1.0;
uniform float omni_wrap = 0.0;
uniform float specular_strength = 0.0;
uniform float shininess = 32.0;
uniform float reflection_emission = 0.0;
uniform vec2 animation_offset = vec2(0.0);
uniform bool animated = false;
uniform bool missing_image = false;
uniform bool environment_uv = false;
uniform vec3 camera_game = vec3(0.0);
uniform bool water_enabled = false;
uniform vec2 water_offsets[32];
uniform vec2 projection_scale = vec2(1.0);
uniform float far_layer = -1.0;

vec3 short_wrap(vec3 value) {
	return mod(value + vec3(32768.0), vec3(65536.0)) - vec3(32768.0);
}

vec3 to_linear(vec3 stored) {
	return mix(stored / 12.92, pow((stored + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), stored));
}

void vertex() {
	vec3 game = VERTEX * vec3(256.0, -256.0, -256.0);
	if (water_enabled && UV2.x >= 0.0) {
		vec2 offset = water_offsets[int(UV2.x)];
		game = short_wrap(game + vec3(offset.x, 0.0, offset.y));
		VERTEX = game / vec3(256.0, -256.0, -256.0);
	}
	vec2 pixel = UV;
	if (animated) {
		pixel = mod(UV + image_origin + animation_offset, vec2(256.0)) - image_origin;
	} else if (environment_uv) {
		pixel = (game.xz + short_wrap(-camera_game).xz) / 32.0 + vec2(128.0) - image_origin;
	} else {
		pixel = mod(UV + image_origin, vec2(256.0)) - image_origin;
	}
	UV = (pixel + image_padding) / image_padded_size;
	if (!IN_SHADOW_PASS) {
		vec4 eye = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		POSITION = PROJECTION_MATRIX * eye;
#ifdef MAP_LIT_FAR
		POSITION.z = POSITION.w * (CLIP_SPACE_FAR + (far_layer + 1.0) * 0.00001);
#else
		vec4 behind = PROJECTION_MATRIX * vec4(eye.xy, eye.z - 128.0 / 256.0, 1.0);
		POSITION.z = behind.z / behind.w * POSITION.w;
#endif
		POSITION.xy *= projection_scale;
	}
}

void fragment() {
	vec4 texel = vec4(1.0);
	if (textured) {
		if (linear_filter) {
			texel = texture(image_linear, UV);
		} else {
			texel = texture(image_nearest, UV);
		}
	}
	vec3 albedo = textured ? texel.rgb * mix(vec3(1.0), to_linear(min(COLOR.rgb * 2.0, vec3(1.0))), vertex_tint) : mix(vec3(1.0), to_linear(COLOR.rgb), vertex_tint);
#ifdef MAP_LIT_QUARTER
	albedo *= 0.25;
#endif
#ifdef MAP_LIT_TRANSLUCENT
	if (texel.a < 0.5 && !missing_image) {
		discard;
	}
#ifdef MAP_LIT_AVERAGE
	ALPHA = 0.5;
#else
	ALPHA = 1.0;
#endif
#else
	ALPHA = missing_image ? 1.0 : texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
	vec3 shown = missing_image ? vec3(0.0) : albedo;
	ALBEDO = shown * (1.0 - reflection_emission);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	EMISSION = shown * reflection_emission;
	if (missing_image) {
		EMISSION = vec3(1.0, 0.0, 1.0);
	}
}

void light() {
	DIFFUSE_LIGHT += mix(max(dot(NORMAL, LIGHT), 0.0), 1.0, omni_wrap * float(!LIGHT_IS_DIRECTIONAL)) * ATTENUATION * LIGHT_COLOR / PI;
	SPECULAR_LIGHT += specular_strength * pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0), shininess) * ATTENUATION * LIGHT_COLOR;
}
