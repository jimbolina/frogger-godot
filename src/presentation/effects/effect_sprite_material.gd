class_name EffectSpriteMaterial
extends RefCounted
## Shared materials, quad batches and camera-plane helpers for the effect views.
##
## Materials come from [ModelShaders] like every other sprite: texture times
## vertex colour times two for textured polygons, the vertex colour as it is
## for untextured ones, stored-colour blending, and [code]depth_bias[/code]
## standing in for the source ordering-table offsets. One ordering slot is
## two game units of view depth (slot = SZ >> 1), so [method slots_bias]
## turns a source OT offset into the bias. [method in_front] makes a variant
## that skips the depth test, for polygons the source placed in the nearest
## fixed slots.

## Horizontal and vertical source focal distances of the 640x480 game view.
const FOCAL_X: float = 512.0
const FOCAL_Y: float = 480.0
## Game units of view depth per ordering-table slot.
const UNITS_PER_SLOT: float = 2.0
## Render priority of the front-most polygons.
const FRONT_PRIORITY: int = 100
## Texture coordinates of source corners 0 1 / 2 3 spanning a whole image.
const UNIT_UVS: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0)]

## One prepared image material with its source size.
class Sprite extends RefCounted:
	var material: ShaderMaterial
	var width: int = 0
	var height: int = 0
	var image: VloImage

	func _init(sprite_material: ShaderMaterial = null, sprite_image: VloImage = null) -> void:
		material = sprite_material
		image = sprite_image
		if sprite_image != null:
			width = sprite_image.width
			height = sprite_image.height

## Accumulated triangle corners, colours and texture coordinates of one material.
class Batch extends RefCounted:
	var positions := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()

	## Appends a quad in source corner order 0 1 / 2 3 with one colour per corner.
	func quad(corners: Array[Vector3], corner_colours: Array[Color], corner_uvs: Array[Vector2] = UNIT_UVS) -> void:
		for corner: int in [0, 1, 2, 2, 1, 3]:
			positions.append(corners[corner])
			colours.append(corner_colours[corner])
			uvs.append(corner_uvs[corner])

	## Appends one triangle.
	func triangle(corners: Array[Vector3], corner_colours: Array[Color]) -> void:
		for corner: int in 3:
			positions.append(corners[corner])
			colours.append(corner_colours[corner])
			uvs.append(Vector2.ZERO)

static var _front_shaders: Dictionary[String, Shader] = {}


## Depth bias for a source ordering-table offset of [param slots] (negative is nearer).
static func slots_bias(slots: int) -> float:
	return -float(slots) * UNITS_PER_SLOT


## A clamped image material with the HIT texel trim of the other sprite views,
## filtered as [param library]'s texture set asks.
static func textured(library: TextureLibrary, image: VloImage, blend: ModelShaders.Blend, depth_bias: float, projection_scale: Vector2) -> ShaderMaterial:
	var material: ShaderMaterial = ModelShaders.material(library.texture_for(image), blend, library.linear_filter(), true)
	var uv: Rect2 = TextureBuilder.uv_rect(image)
	uv.size.x -= (1.0 / image.padded_width) if image.has_flag(VloImage.FLAG_HIT_X) else 0.0
	uv.size.y -= (1.0 / image.padded_height) if image.has_flag(VloImage.FLAG_HIT_Y) else 0.0
	material.set_shader_parameter("uv_scale", uv.size)
	material.set_shader_parameter("uv_offset", uv.position)
	material.set_shader_parameter("projection_scale", projection_scale)
	material.set_shader_parameter("depth_bias", depth_bias)
	return material


## An untextured material drawing vertex colours.
static func untextured(blend: ModelShaders.Blend, depth_bias: float, projection_scale: Vector2) -> ShaderMaterial:
	var material: ShaderMaterial = ModelShaders.material(null, blend, false, true)
	material.set_shader_parameter("projection_scale", projection_scale)
	material.set_shader_parameter("depth_bias", depth_bias)
	return material


## An untextured material that ignores the depth buffer and draws after other translucent polygons.
static func in_front(blend: ModelShaders.Blend, projection_scale: Vector2) -> ShaderMaterial:
	var key: String = str(blend)
	if not _front_shaders.has(key):
		var shader := Shader.new()
		shader.code = ModelShaders.shader_code(false, blend, false, true).replace("render_mode unshaded, ", "render_mode unshaded, depth_test_disabled, ")
		_front_shaders[key] = shader
	var material := ShaderMaterial.new()
	material.shader = _front_shaders[key]
	material.render_priority = FRONT_PRIORITY
	material.set_shader_parameter("projection_scale", projection_scale)
	return material


## The blend of a particle or shadow polygon: always semi-transparent, at the image page's rate.
static func semi_transparent_blend(image: VloImage) -> ModelShaders.Blend:
	return ModelShaders.blend_for_mode(image.blend_mode())


## The blend of a sprite whose translucency follows the image's own flag.
static func image_blend(image: VloImage) -> ModelShaders.Blend:
	return ModelShaders.blend_for_mode(image.blend_mode()) if image.has_flag(VloImage.FLAG_TRANSLUCENT) else ModelShaders.Blend.OPAQUE


## A stored colour from bytes, clamped to 0-255.
static func colour(bytes: Vector3i) -> Color:
	return Color(clampi(bytes.x, 0, 255) / 255.0, clampi(bytes.y, 0, 255) / 255.0, clampi(bytes.z, 0, 255) / 255.0)


## A Godot position from game coordinates that may carry fractions.
static func world(at: Vector3) -> Vector3:
	return Vector3(at.x, -at.y, -at.z) / GameSpace.UNITS_PER_SQUARE


## View depth of game point [param at] from the committed camera, in game units.
static func view_depth(camera: GameplayCameraSnapshot, at: Vector3) -> float:
	return (at - Vector3(camera.source_world)).dot(Vector3(camera.axis_z_12)) / 4096.0


## Game-space offset along the camera's screen axes by [param right] and [param down] game units.
static func screen_offset(camera: GameplayCameraSnapshot, right: float, down: float) -> Vector3:
	return (Vector3(camera.axis_x_12) * right + Vector3(camera.axis_y_12) * down) / 4096.0


## Rebuilds [param mesh] from [param batches]; returns whether anything was drawn.
static func commit(mesh: ImmediateMesh, batches: Dictionary[ShaderMaterial, Batch]) -> bool:
	mesh.clear_surfaces()
	var drawn: bool = false
	for material: ShaderMaterial in batches:
		var batch: Batch = batches[material]
		if batch.positions.is_empty():
			continue
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
		for index: int in batch.positions.size():
			mesh.surface_set_color(batch.colours[index])
			mesh.surface_set_uv(batch.uvs[index])
			mesh.surface_add_vertex(batch.positions[index])
		mesh.surface_end()
		drawn = true
	return drawn


## The batch of [param material] in [param batches], created on first use.
static func batch_for(batches: Dictionary[ShaderMaterial, Batch], material: ShaderMaterial) -> Batch:
	if not batches.has(material):
		batches[material] = Batch.new()
	return batches[material]
