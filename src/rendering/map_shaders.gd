class_name MapShaders
extends RefCounted
## Selects and prepares the lit map terrain and sky shaders under [constant SHADER_DIR].
##
## Terrain samples each image's own padded texture with repeat wrapping. A
## polygon's pixel coordinate keeps the retail byte wrap around the image's
## page origin, then becomes a normalised coordinate inside the padded image:
## [code](pixel + padding) / padded_size[/code]. Godot lights shade the
## result; the shadow pass skips the terrain depth push and projection scaling
## so casters keep their true shape. The unshaded sky samples one
## [Texture2DArray] of its tile images ([MapSkyTiles]) at the layer in
## [code]UV2.x[/code].

## Folder of the map shader files and their shared include.
const SHADER_DIR: String = "res://src/rendering/shaders"
## The shared include of the ten terrain variants.
const INCLUDE_PATH: String = SHADER_DIR + "/map.gdshaderinc"
## Game units ordinary terrain depth moves away from the camera, leaving screen
## positions unchanged. mapdisp.c sorts terrain MAP_POLY_OT_OFFSET (64) ordering
## slots behind its average corner depth after the gameplay viewport's otz shift
## of 1, which is 128 units of view depth.
const TERRAIN_DEPTH_BIAS: float = 128.0

static var _shaders: Dictionary[String, Shader] = {}


## The vertex lines of the include that push ordinary terrain depth back by
## [constant TERRAIN_DEPTH_BIAS] without moving it on screen; far layers and
## the sky keep their own depth.
static func terrain_depth_code() -> String:
	return ("\t\tvec4 behind = PROJECTION_MATRIX * vec4(eye.xy, eye.z - %.1f / 256.0, 1.0);\n" % TERRAIN_DEPTH_BIAS
		+ "\t\tPOSITION.z = behind.z / behind.w * POSITION.w;\n")


## The terrain file for [param blend], with the far-layer push when [param far].
static func shader_path(blend: ModelShaders.Blend, far: bool) -> String:
	return "%s/map_%s%s.gdshader" % [SHADER_DIR, ModelShaders.BLEND_NAMES[blend], "_far" if far else ""]


## The unshaded sky file.
static func sky_shader_path() -> String:
	return SHADER_DIR + "/map_sky.gdshader"


## The terrain variant, loaded once from its file.
static func shader(blend: ModelShaders.Blend, far: bool) -> Shader:
	return _load(shader_path(blend, far))


## The sky shader, loaded once from its file.
static func sky_shader() -> Shader:
	return _load(sky_shader_path())


## Material sampling [param texture], the padded per-image texture of
## [param image] (null for an untextured polygon), filtered linearly with
## mipmaps when [param linear] or when it is a lettering [CanvasTexture]. A
## [param layer] of zero or more draws behind ordinary terrain in that far
## layer.
static func material(image: VloImage, texture: Texture2D, blend: ModelShaders.Blend, linear: bool,
		layer: int) -> ShaderMaterial:
	var drawn: Texture2D = TextureBuilder.source_texture(texture)
	var made := ShaderMaterial.new()
	made.shader = shader(blend, layer >= 0)
	made.set_shader_parameter("textured", image != null)
	made.set_shader_parameter("linear_filter", linear or drawn != texture)
	if image != null:
		made.set_shader_parameter("image_nearest", drawn)
		made.set_shader_parameter("image_linear", drawn)
		made.set_shader_parameter("missing_image", drawn == null)
		made.set_shader_parameter("image_origin", Vector2(image.u, image.v))
		made.set_shader_parameter("image_padding", Vector2(image.left_padding(), image.top_padding()))
		made.set_shader_parameter("image_padded_size", Vector2(image.padded_width, image.padded_height))
	made.set_shader_parameter("far_layer", float(layer))
	if layer >= 0:
		made.render_priority = -127 + layer
	return made


## Sky material sampling the tile array [param tiles] at the layer in
## [code]UV2.x[/code], filtered linearly with mipmaps when [param linear].
## Every tile shares [param padding] and [param padded_size] in retail pixels,
## so the coordinates stay normalised at any texture scale.
static func sky_material(tiles: Texture2DArray, linear: bool, padding: Vector2, padded_size: Vector2) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = sky_shader()
	made.set_shader_parameter("tiles", tiles)
	made.set_shader_parameter("tiles_linear", tiles)
	made.set_shader_parameter("linear_filter", linear)
	made.set_shader_parameter("tile_padding", padding)
	made.set_shader_parameter("tile_padded_size", padded_size)
	made.set_shader_parameter("far_layer", 0.0)
	made.render_priority = -127
	return made


## The vertex lines of the sky that normalise a tile's image-relative pixel
## into its padded layer and pass the layer on. Mirrors [method MapSkyTiles.layer_uv].
static func sky_layer_code() -> String:
	return ("\tUV = (UV + tile_padding) / tile_padded_size;\n"
		+ "\ttile_layer = UV2.x;\n")


## The normalised coordinate inside the padded texture of [param image] that the
## vertex stage gives image-relative [param pixel], adding
## [param animation_offset] as an animated surface does. Mirrors [method uv_code].
static func normalised_uv(pixel: Vector2, image: VloImage, animation_offset: Vector2 = Vector2.ZERO) -> Vector2:
	var origin := Vector2(image.u, image.v)
	var wrapped: Vector2 = (pixel + origin + animation_offset).posmod(256.0) - origin
	return (wrapped + Vector2(image.left_padding(), image.top_padding())) / Vector2(image.padded_width, image.padded_height)


## The normalised coordinate inside the padded texture of [param image] that the
## vertex stage gives an environment-mapped corner at game position
## [param game] seen from [param camera]: the continuous retail formula
## without its per-vertex floor and byte wrap. Mirrors [method uv_code].
static func normalised_environment_uv(game: Vector3, camera: Vector3, image: VloImage) -> Vector2:
	var negative: Vector3 = (-camera + Vector3.ONE * 32768.0).posmod(65536.0) - Vector3.ONE * 32768.0
	var pixel: Vector2 = Vector2(game.x + negative.x, game.z + negative.z) / 32.0 + Vector2(128.0, 128.0) - Vector2(image.u, image.v)
	return (pixel + Vector2(image.left_padding(), image.top_padding())) / Vector2(image.padded_width, image.padded_height)


## The vertex lines of the include that wrap and normalise a polygon's pixel.
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


## The vertex lines of the include that leave the shadow pass on true
## positions and otherwise apply the terrain depth push, far push and projection scale.
static func shadow_gate_code() -> String:
	return ("\tif (!IN_SHADOW_PASS) {\n"
		+ "\t\tvec4 eye = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);\n"
		+ "\t\tPOSITION = PROJECTION_MATRIX * eye;\n"
		+ "#ifdef MAP_FAR\n"
		+ "\t\tPOSITION.z = POSITION.w * (CLIP_SPACE_FAR + (far_layer + 1.0) * 0.00001);\n"
		+ "#else\n"
		+ terrain_depth_code()
		+ "#endif\n"
		+ "\t\tPOSITION.xy *= projection_scale;\n"
		+ "\t}\n")


static func _load(path: String) -> Shader:
	if not _shaders.has(path):
		_shaders[path] = load(path) as Shader
	return _shaders[path]
