shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;


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


uniform vec2 pixel_scale = vec2(1.0);
uniform vec2 pixel_padding = vec2(0.0);
uniform vec2 image_origin = vec2(0.0);
uniform vec2 animation_offset = vec2(0.0);
uniform bool animated = false;
uniform bool missing_image = false;
uniform bool environment_uv = false;
uniform bool cave_enabled = false;
uniform float cave_min_r2 = 1.0;
uniform float cave_max_r2 = 2.0;
uniform vec3 cave_frog = vec3(0.0);
uniform vec3 camera_game = vec3(0.0);
uniform bool water_enabled = false;
uniform vec2 water_offsets[32];
uniform float far_layer = -1.0;
uniform vec2 projection_scale = vec2(1.0);
uniform bool reference_projection = false;
uniform bool sky_backdrop = false;
uniform vec3 sky_drift = vec3(0.0);
varying vec2 affine_uv;
varying vec3 affine_colour;
varying float affine_weight;
varying float reference_visible;

vec3 short_wrap(vec3 value) {
	return mod(value + vec3(32768.0), vec3(65536.0)) - vec3(32768.0);
}

ivec3 reference_rotate(ivec3 value) {
	return ivec3((8192 * value.x) >> 12,
		(5430 * value.y - 5430 * value.z) >> 12,
		(2896 * value.y + 2896 * value.z) >> 12);
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
		pixel = mod(pixel + image_origin + animation_offset, vec2(256.0)) - image_origin;
	} else if (environment_uv) {
		vec3 negative_camera = short_wrap(-camera_game);
		vec3 difference = game + negative_camera;
		pixel = mod(floor(difference.xz / 32.0) + vec2(128.0), vec2(256.0)) - image_origin;
	} else {
		pixel = mod(pixel + image_origin, vec2(256.0)) - image_origin;
	}
	if (sky_backdrop) {
		pixel.y += UV2.x * 258.0 + 1.0;
	}
	vec3 colour = COLOR.rgb;
	if (cave_enabled) {
		vec3 difference = short_wrap(game - cave_frog);
		float distance_r2 = dot(difference, difference);
		float grey = 128.0;
		if (distance_r2 > cave_max_r2) {
			grey = 0.0;
		} else if (distance_r2 >= cave_min_r2 && cave_max_r2 > cave_min_r2) {
			float factor = floor(8388608.0 / (cave_max_r2 - cave_min_r2));
			grey = 128.0 - floor(factor * (distance_r2 - cave_min_r2) / 65536.0);
		}
		colour = vec3(clamp(grey, 0.0, 128.0) / 255.0);
	}
	vec4 eye = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = PROJECTION_MATRIX * eye;
	POSITION.xy *= projection_scale;
	reference_visible = 1.0;
	if (reference_projection) {
		ivec3 view = reference_rotate(ivec3(round(game)));
		if (sky_backdrop) {
			view += reference_rotate(ivec3(sky_drift));
		} else {
			view += reference_rotate(ivec3(short_wrap(-camera_game)));
		}
		int depth = max(view.z, 500);
		ivec2 screen = ivec2(320 + (view.x * 1000) / depth,
			240 + (view.y * 1000) / depth);
		screen = ((screen + ivec2(32768)) & ivec2(65535)) - ivec2(32768);
		POSITION = PROJECTION_MATRIX * vec4(0.0, 0.0, -float(depth) / 256.0, 1.0);
		POSITION.xy = vec2(float(screen.x) / 320.0 - 1.0,
			1.0 - float(screen.y) / 240.0) * POSITION.w
			* vec2(sign(PROJECTION_MATRIX[0][0]), sign(PROJECTION_MATRIX[1][1]));
		if (!sky_backdrop && far_layer < 0.0 && UV2.y >= 3.0) {
			int translation_z = reference_rotate(ivec3(short_wrap(-camera_game))).z;
			ivec4 depths = max(ivec4(round(CUSTOM0)) + ivec4(translation_z), ivec4(500));
			int average = UV2.y == 3.0 ? (1365 * (depths.x + depths.y + depths.z)) >> 12
				: (depths.x + depths.y + depths.z + depths.w) / 4;
			int bucket = (average >> 2) + 64;
			reference_visible = average <= 16 || bucket >= 4096 ? 0.0 : 1.0;
		}
	}
	if (far_layer >= 0.0) {
		POSITION.z = POSITION.w * (CLIP_SPACE_FAR + (far_layer + 1.0) * 0.00001);
	}
	affine_weight = POSITION.w;
	affine_uv = (pixel * pixel_scale + pixel_padding) * POSITION.w;
	affine_colour = colour * POSITION.w;
}

void fragment() {
	if (reference_visible < 0.5) { discard; }
	vec3 shown = (affine_colour / affine_weight);
	if (missing_image) { shown = vec3(1.0, 0.0, 1.0); }
	ALBEDO = through_renderer(clamp(shown, vec3(0.0), vec3(1.0)));
	ALPHA = 0.5;
}
