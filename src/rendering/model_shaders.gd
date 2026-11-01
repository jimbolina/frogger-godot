class_name ModelShaders
extends RefCounted
## The shaders that draw the game's polygons, and materials made from them.
##
## Every polygon keeps the original's colour rules:
## [br]- a textured pixel is the texture's colour times the polygon's colour
##   times two, the polygon's colour stopping at full brightness. A polygon
##   colour of 128 leaves the texture as it is;
## [br]- an untextured pixel is the polygon's colour as it is, not doubled;
## [br]- a texture pixel made transparent by the black-is-transparent rule is
##   not drawn;
## [br]- a translucent polygon is mixed with what is behind it in one of four
##   ways (see [enum Blend]) and does not write depth.
##
## Two families of files under [code]src/rendering/shaders/[/code] draw them,
## each combination of choices its own thin file ([method shader_path]):
## [br]- the lit family [code]model_{textured|flat}_{blend}[_linear][_two_sided][/code],
##   sharing [code]model.gdshaderinc[/code], draws models. Godot's lights shade
##   it: the polygon colour is decoded to linear light, a texture through
##   [code]source_color[/code]. Stored normals point inward, so the shader
##   flips them, and the depth bias and projection scale are skipped in shadow
##   passes. The instance uniforms [constant TINT_SCALE] and
##   [constant TINT_AMBIENT] carry a model's [SceneTint]; the global
##   [constant AMBIENT_GLOBAL] is the scene ambient, added as emission.
## [br]- the unlit family [code]model_unlit_{textured|flat}_{blend}[_linear]_two_sided[/code],
##   sharing [code]model_unlit.gdshaderinc[/code], draws sprites and effects,
##   whose colours were lit on the CPU or not at all. It shows the stored
##   result decoded to linear light, so a linear tone mapper puts the same
##   bytes on screen. Only two-sided unlit files exist, as no sprite is culled.
##
## [code]depth_bias[/code] moves a material's depth toward the camera by that
## many game units without moving it on screen, standing in for a fixed
## ordering-table offset; it is 0 unless a view sets it.

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

## Folder of the shader files.
const SHADER_DIR: String = "res://src/rendering/shaders"
## File-name prefix of an unlit shader in place of [code]model_[/code].
const UNLIT_PREFIX: String = "model_unlit_"
## Instance uniform: the linear colour multiplier of a lit model.
const TINT_SCALE: StringName = &"tint_scale"
## Instance uniform: a lit model's linear custom ambient, alpha one when it replaces the scene ambient.
const TINT_AMBIENT: StringName = &"tint_ambient"
## Global uniform: the scene ambient of lit models, in linear light.
const AMBIENT_GLOBAL: StringName = &"frogger_model_ambient"
## File-name word for each [enum Blend].
const BLEND_NAMES: PackedStringArray = ["opaque", "average", "add", "subtract", "add_quarter"]

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


## The shader file for one combination of choices; filtering only matters for
## a textured one, and an unlit file is always two-sided.
static func shader_path(textured: bool, blend: Blend, linear_filter: bool, two_sided: bool, lit: bool = true) -> String:
	return "%s/%s%s_%s%s%s.gdshader" % [SHADER_DIR, "model_" if lit else UNLIT_PREFIX, "textured" if textured else "flat",
		BLEND_NAMES[blend], "_linear" if linear_filter and textured else "", "_two_sided" if two_sided or not lit else ""]


## The shader for one combination of choices, loaded once from its file.
static func shader(textured: bool, blend: Blend, linear_filter: bool, two_sided: bool, lit: bool = true) -> Shader:
	var path: String = shader_path(textured, blend, linear_filter, two_sided, lit)
	if not _shaders.has(path):
		_shaders[path] = load(path) as Shader
	return _shaders[path]


## The linear, mipmapped variant of the textured model shader [param source]
## (itself for a flat shader, a variant that already filters linearly, or a
## shader that is not one of the files).
static func linear_variant(source: Shader) -> Shader:
	if source == null:
		return null
	var path: String = source.resource_path
	var name: String = path.get_file()
	if path.get_base_dir() != SHADER_DIR or not (name.begins_with("model_textured_") or name.begins_with(UNLIT_PREFIX + "textured_")) \
			or name.contains("_linear"):
		return source
	var two_sided: String = "_two_sided.gdshader"
	var linear: String = path.trim_suffix(two_sided).trim_suffix(".gdshader") + "_linear" + (two_sided if path.ends_with(two_sided) else ".gdshader")
	if not _shaders.has(linear):
		_shaders[linear] = load(linear) as Shader
	return _shaders[linear]


## The text of the unlit shader for one combination of choices with its
## include written out, for views that build a variant by editing the text.
static func shader_code(textured: bool, blend: Blend, linear_filter: bool) -> String:
	var path: String = shader_path(textured, blend, linear_filter, true, false)
	var code: String = shader(textured, blend, linear_filter, true, false).code
	var expanded := PackedStringArray()
	for line: String in code.split("\n"):
		if line.begins_with("#include \""):
			var include: ShaderInclude = load(path.get_base_dir().path_join(line.trim_prefix("#include \"").trim_suffix("\""))) as ShaderInclude
			expanded.append(include.code.trim_suffix("\n"))
		else:
			expanded.append(line)
	return "\n".join(expanded)


## A material drawing with [param texture] (null for untextured polygons),
## through the lit family when [param lit] and the unlit one otherwise.
static func material(texture: Texture2D, blend: Blend, linear_filter: bool, two_sided: bool, lit: bool = true) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = shader(texture != null, blend, linear_filter, two_sided, lit)
	if texture != null:
		made.set_shader_parameter("image", texture)
	return made
