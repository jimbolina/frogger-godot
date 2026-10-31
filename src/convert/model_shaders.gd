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
## [code]depth_bias[/code] moves a material's depth toward the camera by that
## many game units without moving it on screen, standing in for a fixed
## ordering-table offset; it is 0 unless a view sets it.
##
## Each combination of choices is its own file under
## [code]src/convert/shaders/[/code] ([method shader_path]), edited directly.
## Their [code]through_renderer[/code] applies the Compatibility correction only
## on that renderer; elsewhere it is the exact sRGB decode, so an unshaded
## surface shows the same bytes under a linear tone mapper.
##
## The modern rendering profile draws through the lit family under
## [code]modern/[/code] ([method lit_variant]): one thin file per retail file
## with the same blend, depth and culling, sharing [code]model_lit.gdshaderinc[/code].
## Godot's lights shade them; the polygon colour is decoded to linear light, a
## texture through [code]source_color[/code]. Stored normals point inward, so
## the shader flips them, and the depth bias and projection scale are skipped
## in shadow passes. The instance uniforms [constant TINT_SCALE] and
## [constant TINT_AMBIENT] carry a model's [SceneTint]; the global
## [constant AMBIENT_GLOBAL] is the scene ambient.

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
const SHADER_DIR: String = "res://src/convert/shaders"
## Folder of the lit shader files of the modern rendering profile.
const LIT_SHADER_DIR: String = "res://src/convert/shaders/modern"
## File-name prefix of a lit shader in place of [code]model_[/code].
const LIT_PREFIX: String = "model_lit_"
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


## The shader file for one combination of choices; filtering only matters for a textured one.
static func shader_path(textured: bool, blend: Blend, linear_filter: bool, two_sided: bool) -> String:
	return "%s/model_%s_%s%s%s.gdshader" % [SHADER_DIR, "textured" if textured else "flat", BLEND_NAMES[blend],
		"_linear" if linear_filter and textured else "", "_two_sided" if two_sided else ""]


## The shader for one combination of choices, loaded once from its file.
static func shader(textured: bool, blend: Blend, linear_filter: bool, two_sided: bool) -> Shader:
	var path: String = shader_path(textured, blend, linear_filter, two_sided)
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
	if not path.begins_with(SHADER_DIR) or not name.begins_with("model_textured_") or name.contains("_linear"):
		return source
	var two_sided: String = "_two_sided.gdshader"
	var linear: String = path.trim_suffix(two_sided).trim_suffix(".gdshader") + "_linear" + (two_sided if path.ends_with(two_sided) else ".gdshader")
	if not _shaders.has(linear):
		_shaders[linear] = load(linear) as Shader
	return _shaders[linear]


## The lit variant under [constant LIT_SHADER_DIR] of the retail model shader
## [param source] (itself for a lit shader or a shader that is not one of the
## retail model files).
static func lit_variant(source: Shader) -> Shader:
	if source == null:
		return null
	var path: String = source.resource_path
	var name: String = path.get_file()
	if path.get_base_dir() != SHADER_DIR or not name.begins_with("model_"):
		return source
	var lit: String = LIT_SHADER_DIR.path_join(LIT_PREFIX + name.trim_prefix("model_"))
	if not _shaders.has(lit):
		_shaders[lit] = load(lit) as Shader
	return _shaders[lit]


## True when [param source] is one of the lit model shaders.
static func is_lit(source: Shader) -> bool:
	return source != null and source.resource_path.get_base_dir() == LIT_SHADER_DIR \
		and source.resource_path.get_file().begins_with(LIT_PREFIX)


## The text of the shader file for one combination of choices.
static func shader_code(textured: bool, blend: Blend, linear_filter: bool, two_sided: bool) -> String:
	return shader(textured, blend, linear_filter, two_sided).code


## A material drawing with [param texture] (null for untextured polygons),
## through the lit variant when [param lit].
static func material(texture: Texture2D, blend: Blend, linear_filter: bool, two_sided: bool, lit: bool = false) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	var chosen: Shader = shader(texture != null, blend, linear_filter, two_sided)
	made.shader = lit_variant(chosen) if lit else chosen
	if texture != null:
		made.set_shader_parameter("image", texture)
	return made
