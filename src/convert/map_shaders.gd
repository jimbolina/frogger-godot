class_name MapShaders
extends RefCounted
## Affine map colours/UVs, byte wrapping, cave grey, ordering layers and terrain depth bias.
## The files under [code]src/convert/shaders/[/code] reuse the model renderer's stored-colour
## correction and blend kernels with the map's own vertex stage.

## Game units ordinary terrain depth moves away from the camera, leaving screen
## positions unchanged. mapdisp.c sorts terrain MAP_POLY_OT_OFFSET (64) ordering
## slots behind its average corner depth after the gameplay viewport's otz shift
## of 1, which is 128 units of view depth.
const TERRAIN_DEPTH_BIAS: float = 128.0
static var _shaders: Dictionary[String, Shader] = {}


## The vertex lines in every ordinary terrain shader file that push depth back by
## [constant TERRAIN_DEPTH_BIAS] without moving it on screen; far layers, the sky and the
## reference projection keep their own depth.
static func terrain_depth_code() -> String:
	return ("\tif (!reference_projection) {\n"
		+ "\t\tvec4 behind = PROJECTION_MATRIX * vec4(eye.xy, eye.z - %.1f / 256.0, 1.0);\n" % TERRAIN_DEPTH_BIAS
		+ "\t\tPOSITION.z = behind.z / behind.w * POSITION.w;\n"
		+ "\t}\n")


## The shader file of one map variant; filtering only matters for a textured one.
static func shader_path(textured: bool, blend: ModelShaders.Blend, linear_filter: bool, far_layer: bool) -> String:
	return "%s/map_%s_%s%s%s.gdshader" % [ModelShaders.SHADER_DIR, "textured" if textured else "flat",
		ModelShaders.BLEND_NAMES[blend], "_linear" if linear_filter and textured else "", "_far" if far_layer else ""]


## The shader file of the sky variant.
static func sky_shader_path(linear_filter: bool) -> String:
	return "%s/map_sky%s.gdshader" % [ModelShaders.SHADER_DIR, "_linear" if linear_filter else ""]


## The map shader variant, loaded once from its file.
static func shader(textured: bool, blend: ModelShaders.Blend, linear_filter: bool, far_layer: bool) -> Shader:
	return _load(shader_path(textured, blend, linear_filter, far_layer))


## Source sky tiles draw without backface rejection in one ordered atlas draw.
static func sky_shader(linear_filter: bool) -> Shader:
	return _load(sky_shader_path(linear_filter))


## Material using retail pixel-space UVs, so byte wrapping and animation stay in
## retail pixels at any page scale; [code]texel_inset[/code] is half a stored
## texel of the bound page, which the linear variants subtract before sampling.
## Translucency is a polygon flag for maps.
static func material(image: VloImage, blend: ModelShaders.Blend, linear_filter: bool, layer: int,
		pages: MapTexturePages) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = shader(image != null, blend, linear_filter, layer >= 0)
	if image != null:
		var texture: Texture2D = pages.texture_for(image)
		made.set_shader_parameter("image", texture)
		made.set_shader_parameter("missing_image", texture == null)
		made.set_shader_parameter("pixel_scale", Vector2.ONE / 256.0)
		made.set_shader_parameter("pixel_padding", Vector2(image.u, image.v) / 256.0)
		made.set_shader_parameter("image_origin", Vector2(image.u, image.v))
		made.set_shader_parameter("texel_inset", texel_inset(texture))
	made.set_shader_parameter("far_layer", float(layer))
	if layer >= 0:
		made.render_priority = -127 + layer
	return made


## Half a texel of [param texture] in normalised coordinates, or zero without one.
static func texel_inset(texture: Texture2D) -> Vector2:
	return Vector2(0.5, 0.5) / texture.get_size() if texture != null else Vector2.ZERO


static func _load(path: String) -> Shader:
	if not _shaders.has(path):
		_shaders[path] = load(path) as Shader
	return _shaders[path]
