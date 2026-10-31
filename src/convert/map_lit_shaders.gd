class_name MapLitShaders
extends RefCounted
## Selects and prepares the modern profile's lit map shaders under
## [constant LIT_SHADER_DIR].
##
## Terrain samples each image's own padded texture with repeat wrapping instead
## of a reconstructed PC page. A polygon's pixel coordinate keeps the retail
## byte wrap around the image's page origin, then becomes a normalised
## coordinate inside the padded image: [code](pixel + padding) / padded_size[/code].
## Godot lights shade the result; the shadow pass skips the retail depth push
## and projection scaling so casters keep their true shape.

## Folder of the lit map shader files and their shared include.
const LIT_SHADER_DIR: String = "res://src/convert/shaders/modern"
## The shared include of the ten terrain variants.
const INCLUDE_PATH: String = LIT_SHADER_DIR + "/map_lit.gdshaderinc"

static var _shaders: Dictionary[String, Shader] = {}


## The lit terrain file for [param blend], with the far-layer push when [param far].
static func shader_path(blend: ModelShaders.Blend, far: bool) -> String:
	return "%s/map_lit_%s%s.gdshader" % [LIT_SHADER_DIR, ModelShaders.BLEND_NAMES[blend], "_far" if far else ""]


## The unshaded lit-profile sky file.
static func sky_shader_path() -> String:
	return "%s/map_lit_sky.gdshader" % LIT_SHADER_DIR


## The lit terrain variant, loaded once from its file.
static func shader(blend: ModelShaders.Blend, far: bool) -> Shader:
	return _load(shader_path(blend, far))


## The lit-profile sky shader, loaded once from its file.
static func sky_shader() -> Shader:
	return _load(sky_shader_path())


## Material sampling [param texture], the padded per-image texture of
## [param image] (null for an untextured polygon), filtered linearly with
## mipmaps when [param linear]. A [param layer] of zero or more draws behind
## ordinary terrain in that far layer, as the retail shaders do.
static func material(image: VloImage, texture: Texture2D, blend: ModelShaders.Blend, linear: bool,
		layer: int) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = shader(blend, layer >= 0)
	made.set_shader_parameter("textured", image != null)
	made.set_shader_parameter("linear_filter", linear)
	if image != null:
		made.set_shader_parameter("image_nearest", texture)
		made.set_shader_parameter("image_linear", texture)
		made.set_shader_parameter("missing_image", texture == null)
		made.set_shader_parameter("image_origin", Vector2(image.u, image.v))
		made.set_shader_parameter("image_padding", Vector2(image.left_padding(), image.top_padding()))
		made.set_shader_parameter("image_padded_size", Vector2(image.padded_width, image.padded_height))
	made.set_shader_parameter("far_layer", float(layer))
	if layer >= 0:
		made.render_priority = -127 + layer
	return made


## Sky material sampling the baked page [param atlas], whose slots hold
## [constant TexturePageSet.SKY_SLOT_HEIGHT] retail rows each at any page scale.
static func sky_material(atlas: Texture2D, linear: bool) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = sky_shader()
	made.set_shader_parameter("image_nearest", atlas)
	made.set_shader_parameter("image_linear", atlas)
	made.set_shader_parameter("linear_filter", linear)
	made.set_shader_parameter("missing_image", atlas == null)
	if atlas != null:
		made.set_shader_parameter("pixel_scale", Vector2(1.0 / TexturePageSet.PAGE_SIZE,
			float(atlas.get_width()) / (TexturePageSet.PAGE_SIZE * atlas.get_height())))
	made.set_shader_parameter("texel_inset", MapShaders.texel_inset(atlas))
	made.set_shader_parameter("far_layer", 0.0)
	made.render_priority = -127
	return made


## The normalised coordinate inside the padded texture of [param image] that the
## lit vertex stage gives image-relative [param pixel], adding
## [param animation_offset] as an animated surface does. Mirrors [method uv_code].
static func normalised_uv(pixel: Vector2, image: VloImage, animation_offset: Vector2 = Vector2.ZERO) -> Vector2:
	var origin := Vector2(image.u, image.v)
	var wrapped: Vector2 = (pixel + origin + animation_offset).posmod(256.0) - origin
	return (wrapped + Vector2(image.left_padding(), image.top_padding())) / Vector2(image.padded_width, image.padded_height)


## The vertex lines of the lit include that wrap and normalise a polygon's pixel.
static func uv_code() -> String:
	return ("\tvec2 pixel = UV;\n"
		+ "\tif (animated) {\n"
		+ "\t\tpixel = mod(UV + image_origin + animation_offset, vec2(256.0)) - image_origin;\n"
		+ "\t} else if (environment_uv) {\n"
		+ "\t\tpixel = (game.xz + short_wrap(-camera_game).xz) / 32.0 + vec2(128.0) - image_origin;\n"
		+ "\t} else {\n"
		+ "\t\tpixel = mod(UV + image_origin, vec2(256.0)) - image_origin;\n"
		+ "\t}\n"
		+ "\tUV = (pixel + image_padding) / image_padded_size;\n")


## The vertex lines of the lit include that leave the shadow pass on true
## positions and otherwise apply the retail depth push, far push and projection scale.
static func shadow_gate_code() -> String:
	return ("\tif (!IN_SHADOW_PASS) {\n"
		+ "\t\tvec4 eye = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);\n"
		+ "\t\tPOSITION = PROJECTION_MATRIX * eye;\n"
		+ "#ifdef MAP_LIT_FAR\n"
		+ "\t\tPOSITION.z = POSITION.w * (CLIP_SPACE_FAR + (far_layer + 1.0) * 0.00001);\n"
		+ "#else\n"
		+ "\t\tvec4 behind = PROJECTION_MATRIX * vec4(eye.xy, eye.z - %.1f / 256.0, 1.0);\n" % MapShaders.TERRAIN_DEPTH_BIAS
		+ "\t\tPOSITION.z = behind.z / behind.w * POSITION.w;\n"
		+ "#endif\n"
		+ "\t\tPOSITION.xy *= projection_scale;\n"
		+ "\t}\n")


static func _load(path: String) -> Shader:
	if not _shaders.has(path):
		_shaders[path] = load(path) as Shader
	return _shaders[path]
