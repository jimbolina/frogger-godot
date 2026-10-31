extends SceneTree
## Writes every shader variant the game draws with to [code]src/convert/shaders/[/code].
##
##   godot --headless --path . -s res://archive/tools/migrate_shaders.gd [-- --check]
##
## A one-time migration: the model and map shaders used to be put together
## from text templates at run time. This script holds those templates and
## writes each variant, fully expanded, to the file
## [method ModelShaders.shader_path], [method MapShaders.shader_path] or
## [method MapShaders.sky_shader_path] names. The game now only loads the
## files, which are edited directly. [code]--check[/code] compares instead of
## writing and exits 1 on a difference; it only holds until a file is edited.

const _MODEL_VERTEX: String = """uniform vec2 projection_scale = vec2(1.0);
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
"""

const _TEMPLATE: String = """shader_type spatial;
render_mode unshaded, %s, %s, %s;
%s
%s
vec3 through_renderer(vec3 wanted) {
	vec3 linear = pow((wanted + 0.055) / 1.055, vec3(2.4));
	vec3 a = wanted;
	for (int i = 0; i < 4; i++) {
		vec3 value = a * (a * (a * 0.305306011 + 0.682171111) + 0.012522878) - linear;
		vec3 slope = a * (a * 0.915918033 + 1.364342222) + 0.012522878;
		a -= value / slope;
	}
	return max(a, vec3(0.0));
}

void fragment() {
%s
	ALBEDO = through_renderer(clamp(shown, vec3(0.0), vec3(1.0)));
%s}
"""
const _TEXTURED_UNIFORM: String = "uniform sampler2D image : %s, repeat_disable;\nuniform vec2 uv_scale = vec2(1.0);\nuniform vec2 uv_offset = vec2(0.0);\n"
const _TEXTURED_BODY: String = """	vec4 texel = texture(image, UV * uv_scale + uv_offset);
	if (texel.a < 0.5) {
		discard;
	}
	vec3 shown = texel.rgb * min(COLOR.rgb * 2.0, vec3(1.0))%s;"""
const _UNTEXTURED_BODY: String = "	vec3 shown = COLOR.rgb%s;"
const BLENDS: Array[ModelShaders.Blend] = [ModelShaders.Blend.OPAQUE, ModelShaders.Blend.AVERAGE,
	ModelShaders.Blend.ADD, ModelShaders.Blend.SUBTRACT, ModelShaders.Blend.ADD_QUARTER]
const _PROJECT_LINE: String = "\tPOSITION = PROJECTION_MATRIX * eye;\n"
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


func _init() -> void:
	var check: bool = OS.get_cmdline_user_args().has("--check")
	var files: Dictionary[String, String] = {}
	for textured: bool in [false, true]:
		for blend: ModelShaders.Blend in BLENDS:
			for linear_filter: bool in ([false, true] if textured else [false]):
				for two_sided: bool in [false, true]:
					files[ModelShaders.shader_path(textured, blend, linear_filter, two_sided)] = model_code(textured, blend, linear_filter, two_sided)
				for far_layer: bool in [false, true]:
					files[MapShaders.shader_path(textured, blend, linear_filter, far_layer)] = map_code(textured, blend, linear_filter, far_layer)
	for linear_filter: bool in [false, true]:
		files[MapShaders.sky_shader_path(linear_filter)] = map_code(true, ModelShaders.Blend.OPAQUE, linear_filter, true).replace("cull_back", "cull_disabled")
	var differing: int = 0
	for path: String in files:
		var existing: String = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
		if existing == files[path]:
			continue
		differing += 1
		if check:
			print("migrate_shaders: %s differs" % path)
			continue
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(files[path])
		file.close()
	print("migrate_shaders: %d variants, %d %s" % [files.size(), differing, "differ" if check else "written"])
	quit(1 if check and differing > 0 else 0)


## The model shader text for one combination of choices.
static func model_code(textured: bool, blend: ModelShaders.Blend, linear_filter: bool, two_sided: bool) -> String:
	var blend_mode: String = "blend_mix"
	if blend == ModelShaders.Blend.ADD or blend == ModelShaders.Blend.ADD_QUARTER:
		blend_mode = "blend_add"
	elif blend == ModelShaders.Blend.SUBTRACT:
		blend_mode = "blend_sub"
	var depth: String = "depth_draw_opaque" if blend == ModelShaders.Blend.OPAQUE else "depth_draw_never"
	var cull: String = "cull_disabled" if two_sided else "cull_back"
	var scale: String = " * 0.25" if blend == ModelShaders.Blend.ADD_QUARTER else ""
	var alpha: String = ""
	if blend == ModelShaders.Blend.AVERAGE:
		alpha = "	ALPHA = 0.5;\n"
	elif blend != ModelShaders.Blend.OPAQUE:
		alpha = "	ALPHA = 1.0;\n"
	var uniform: String = ""
	var body: String = _UNTEXTURED_BODY % scale
	if textured:
		uniform = _TEXTURED_UNIFORM % ("filter_linear" if linear_filter else "filter_nearest")
		body = _TEXTURED_BODY % scale
	return _TEMPLATE % [blend_mode, depth, cull, uniform, _MODEL_VERTEX, body, alpha]


## The map shader text: the model recipe with the map's vertex stage.
static func map_code(textured: bool, blend: ModelShaders.Blend, linear_filter: bool, far_layer: bool) -> String:
	var code: String = model_code(textured, blend, linear_filter, false)
	code = code.replace(_MODEL_VERTEX, "")
	var vertex: String = _VERTEX if far_layer else _VERTEX.replace(_PROJECT_LINE, _PROJECT_LINE + _terrain_depth_code())
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
	return code


static func _terrain_depth_code() -> String:
	return ("\tif (!reference_projection) {\n"
		+ "\t\tvec4 behind = PROJECTION_MATRIX * vec4(eye.xy, eye.z - %.1f / 256.0, 1.0);\n" % MapShaders.TERRAIN_DEPTH_BIAS
		+ "\t\tPOSITION.z = behind.z / behind.w * POSITION.w;\n"
		+ "\t}\n")
