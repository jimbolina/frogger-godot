class_name ModelShaders
extends RefCounted
## The shaders that draw the game's polygons, and materials made from them.
##
## The original drew with a fixed recipe, which these shaders repeat:
## [br]- a textured pixel is the texture's colour times the polygon's colour
##   times two, the polygon's colour stopping at full brightness. A polygon
##   colour of 128 leaves the texture as it is;
## [br]- an untextured pixel is the polygon's colour as it is, not doubled;
## [br]- a texture pixel made transparent by the black-is-transparent rule is
##   not drawn;
## [br]- a translucent polygon is mixed with what is behind it in one of four
##   ways (see [enum Blend]) and does not write depth.
## [br]The arithmetic is done on the colour values as stored, the way the
## original did it. Textures are read without Godot's colour conversion. The
## project's renderer (Compatibility) takes a shader's colour as a stored
## value too, but converts it to linear light and back on the way to the
## screen, with two approximations that darken dark colours (20 comes out as
## 16). The shader undoes that beforehand ([code]through_renderer[/code], from
## the formulas in Godot 4.5's [code]drivers/gles3/shaders[/code]). Mixing with
## what is behind happens after all this, on stored values, as in the
## original. [code]tools/probe_model_shader.gd[/code] measures the result; run
## it again after changing the Godot version, the renderer, or adding an
## environment.
##
## Lighting is supplied as vertex colours by the optional map-light model
## converter. Standalone model viewers use the polygon's own colour.
##
## Shaders are written out from one template, one per combination of
## choices, and kept.

## How a polygon is combined with what is behind it.
enum Blend {
	## Not translucent.
	OPAQUE,
	## Half of each (texture blend mode 0).
	AVERAGE,
	## Added (mode 1).
	ADD,
	## Subtracted (mode 2).
	SUBTRACT,
	## A quarter added (mode 3).
	ADD_QUARTER,
}

## Model-only vertex stage, replaced wholesale by the map shader.
const VERTEX_CODE: String = """uniform vec2 projection_scale = vec2(1.0);
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

static var _shaders: Dictionary[String, Shader] = {}


## The blend for a texture's blend mode number (0 to 3).
static func blend_for_mode(blend_mode: int) -> Blend:
	match blend_mode:
		1:
			return Blend.ADD
		2:
			return Blend.SUBTRACT
		3:
			return Blend.ADD_QUARTER
	return Blend.AVERAGE


## The shader text for one combination of choices.
static func shader_code(textured: bool, blend: Blend, linear_filter: bool, two_sided: bool) -> String:
	var blend_mode: String = "blend_mix"
	if blend == Blend.ADD or blend == Blend.ADD_QUARTER:
		blend_mode = "blend_add"
	elif blend == Blend.SUBTRACT:
		blend_mode = "blend_sub"
	var depth: String = "depth_draw_opaque" if blend == Blend.OPAQUE else "depth_draw_never"
	var cull: String = "cull_disabled" if two_sided else "cull_back"
	var scale: String = " * 0.25" if blend == Blend.ADD_QUARTER else ""
	var alpha: String = ""
	if blend == Blend.AVERAGE:
		alpha = "	ALPHA = 0.5;\n"
	elif blend != Blend.OPAQUE:
		alpha = "	ALPHA = 1.0;\n"
	var uniform: String = ""
	var body: String = _UNTEXTURED_BODY % scale
	if textured:
		uniform = _TEXTURED_UNIFORM % ("filter_linear" if linear_filter else "filter_nearest")
		body = _TEXTURED_BODY % scale
	return _TEMPLATE % [blend_mode, depth, cull, uniform, VERTEX_CODE, body, alpha]


## The shader for one combination of choices (made once, then reused).
static func shader(textured: bool, blend: Blend, linear_filter: bool, two_sided: bool) -> Shader:
	var key: String = "%s/%d/%s/%s" % [textured, blend, linear_filter and textured, two_sided]
	if not _shaders.has(key):
		var made := Shader.new()
		made.code = shader_code(textured, blend, linear_filter, two_sided)
		_shaders[key] = made
	return _shaders[key]


## A material drawing with [param texture] (null for untextured polygons).
static func material(texture: Texture2D, blend: Blend, linear_filter: bool, two_sided: bool) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = shader(texture != null, blend, linear_filter, two_sided)
	if texture != null:
		made.set_shader_parameter("image", texture)
	return made
