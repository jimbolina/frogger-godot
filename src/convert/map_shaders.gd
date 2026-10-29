class_name MapShaders
extends RefCounted
## Affine map colours/UVs, byte wrapping, cave grey, ordering layers and terrain depth bias.
## Reuses the model renderer's stored-colour correction and blend kernels.

## Game units ordinary terrain depth moves away from the camera, leaving screen
## positions unchanged. mapdisp.c sorts terrain MAP_POLY_OT_OFFSET (64) ordering
## slots behind its average corner depth after the gameplay viewport's otz shift
## of 1, which is 128 units of view depth.
const TERRAIN_DEPTH_BIAS: float = 128.0
const _PROJECT_LINE: String = "\tPOSITION = PROJECTION_MATRIX * eye;\n"

static var _shaders: Dictionary[String, Shader] = {}

const _VERTEX: String = """
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
"""


## Vertex lines that push ordinary terrain depth back by [constant TERRAIN_DEPTH_BIAS]
## without moving it on screen; far layers and the reference projection keep their own depth.
static func terrain_depth_code() -> String:
	return ("\tif (!reference_projection) {\n"
		+ "\t\tvec4 behind = PROJECTION_MATRIX * vec4(eye.xy, eye.z - %.1f / 256.0, 1.0);\n" % TERRAIN_DEPTH_BIAS
		+ "\t\tPOSITION.z = behind.z / behind.w * POSITION.w;\n"
		+ "\t}\n")


## Shader variant with the same colour correction and blend arithmetic as models.
static func shader(textured: bool, blend: ModelShaders.Blend, linear_filter: bool, far_layer: bool) -> Shader:
	var key: String = "%s/%d/%s/%s" % [textured, blend, linear_filter, far_layer]
	if not _shaders.has(key):
		var code: String = ModelShaders.shader_code(textured, blend, linear_filter, false)
		code = code.replace(ModelShaders.VERTEX_CODE, "")
		var vertex: String = _VERTEX if far_layer else _VERTEX.replace(_PROJECT_LINE, _PROJECT_LINE + terrain_depth_code())
		code = code.replace("void fragment() {", vertex + "\nvoid fragment() {")
		code = code.replace("void fragment() {", "void fragment() {\n\tif (reference_visible < 0.5) { discard; }")
		code = code.replace("UV * uv_scale + uv_offset", "affine_uv / affine_weight")
		if linear_filter:
			code = code.replace("texture(image, affine_uv / affine_weight)",
				"texture(image, affine_uv / affine_weight - pixel_scale * 0.5)")
		code = code.replace("COLOR.rgb", "(affine_colour / affine_weight)")
		code = code.replace("if (texel.a < 0.5)", "if (texel.a < 0.5 && !missing_image)")
		code = code.replace("ALBEDO = through_renderer", "if (missing_image) { shown = vec3(1.0, 0.0, 1.0); }\n\tALBEDO = through_renderer")
		code = code.replace("vec3 colour = (affine_colour / affine_weight);", "vec3 colour = COLOR.rgb;")
		if far_layer and blend == ModelShaders.Blend.OPAQUE:
			code = code.replace("depth_draw_opaque", "depth_draw_never")
			code = code.replace("ALBEDO = through_renderer", "ALPHA = 1.0;\n\tALBEDO = through_renderer")
		var made := Shader.new()
		made.code = code
		_shaders[key] = made
	return _shaders[key]


## Source sky tiles draw without backface rejection in one ordered atlas draw.
static func sky_shader(linear_filter: bool) -> Shader:
	var key: String = "sky/%s" % linear_filter
	if not _shaders.has(key):
		var made := Shader.new()
		made.code = shader(true, ModelShaders.Blend.OPAQUE, linear_filter, true).code.replace("cull_back", "cull_disabled")
		_shaders[key] = made
	return _shaders[key]


## Material using pixel-space UVs; translucency is a polygon flag for maps.
static func material(image: VloImage, library: TextureLibrary, blend: ModelShaders.Blend,
		linear_filter: bool, layer: int = -1, pages: MapTexturePages = null) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = shader(image != null, blend, linear_filter, layer >= 0)
	if image != null:
		if pages != null:
			var texture: ImageTexture = pages.texture_for(image)
			made.set_shader_parameter("image", texture)
			made.set_shader_parameter("missing_image", texture == null)
			made.set_shader_parameter("pixel_scale", Vector2.ONE / 256.0)
			made.set_shader_parameter("pixel_padding", Vector2(image.u, image.v) / 256.0)
		else:
			made.set_shader_parameter("image", library.texture_for(image))
			made.set_shader_parameter("pixel_scale", Vector2(1.0 / image.padded_width, 1.0 / image.padded_height))
			made.set_shader_parameter("pixel_padding", Vector2(float(image.left_padding()) / image.padded_width,
				float(image.top_padding()) / image.padded_height))
		made.set_shader_parameter("image_origin", Vector2(image.u, image.v))
	made.set_shader_parameter("far_layer", float(layer))
	if layer >= 0:
		made.render_priority = -127 + layer
	return made
