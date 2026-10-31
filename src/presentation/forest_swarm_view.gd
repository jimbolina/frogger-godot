class_name ForestSwarmView
extends MeshInstance3D
## Draws the three source swarm sprites from committed hive and camera samples.

var _sprites := ImmediateMesh.new()
var _material: ShaderMaterial
var _state: GameplayState

## Resolves the supplied named image without retaining player data or advancing rules.
func configure(scene: MapSceneData, data: AssetCatalog) -> String:
	clear()
	if scene == null or data == null or data.names.images == null:
		return "Forest swarms require named player textures"
	var identity: int = data.names.images.index_of("for_swarm")
	var image: VloImage = scene.library.image_for_id(identity, scene.preferred)
	if image == null:
		return "Forest swarm image for_swarm is missing from the supplied banks"
	_material = ModelShaders.material(scene.library.texture_for(image), ModelShaders.Blend.OPAQUE, false, true)
	var uv: Rect2 = TextureBuilder.uv_rect(image)
	uv.size.x -= (1.0 / image.padded_width) if image.has_flag(VloImage.FLAG_HIT_X) else 0.0
	uv.size.y -= (1.0 / image.padded_height) if image.has_flag(VloImage.FLAG_HIT_Y) else 0.0
	_material.set_shader_parameter("uv_scale", uv.size)
	_material.set_shader_parameter("uv_offset", uv.position)
	return ""

## Releases source-replacement drawing state and any retained snapshot.
func clear() -> void:
	_state = null
	_material = null
	_sprites.clear_surfaces()
	visible = false

## Applies the same source projection correction as terrain and models.
func set_projection_scale(scale: Vector2) -> void:
	if _material != null:
		_material.set_shader_parameter("projection_scale", scale)

## Rebuilds sprites only for a new committed state; repeated rendering is inert.
func draw_state(state: GameplayState) -> void:
	if state == _state:
		return
	_state = state
	_sprites.clear_surfaces()
	visible = false
	if state == null or state.entities == null or state.camera == null or _material == null:
		return
	var opened: bool = false
	for entity: EntitySnapshot in state.entities.entities:
		if not entity.live or entity.custom_state == null or entity.custom_state.swarm == null:
			continue
		var swarm: EntitySwarmState = entity.custom_state.swarm
		if not swarm.visible or swarm.positions.size() != 3 or swarm.matrix12.size() != 12:
			continue
		if not opened:
			_sprites.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
			opened = true
		var offsets: Array[Vector3i] = sprite_offsets(swarm.matrix12, state.camera)
		for centre: Vector3i in swarm.positions:
			_vertex(centre + offsets[0], Vector2(0.0, 0.0))
			_vertex(centre + offsets[1], Vector2(1.0, 0.0))
			_vertex(centre + offsets[2], Vector2(0.0, 1.0))
			_vertex(centre + offsets[2], Vector2(0.0, 1.0))
			_vertex(centre + offsets[1], Vector2(1.0, 0.0))
			_vertex(centre + offsets[3], Vector2(1.0, 1.0))
	if opened:
		_sprites.surface_end()
		mesh = _sprites
		visible = true

## Projects source forward onto camera XY without normalizing the sprite axes.
static func sprite_offsets(matrix12: PackedInt32Array, camera: GameplayCameraSnapshot) -> Array[Vector3i]:
	var forward := Vector3i(matrix12[2], matrix12[5], matrix12[8])
	var dx: int = _dot12(forward, camera.axis_x_12)
	var dy: int = _dot12(forward, camera.axis_y_12)
	var axis_y := Vector3i(
		PlatformMath.s16(PlatformMath.s32(-(dx * camera.axis_x_12.x + dy * camera.axis_y_12.x)) >> 12),
		PlatformMath.s16(PlatformMath.s32(-(dx * camera.axis_x_12.y + dy * camera.axis_y_12.y)) >> 12),
		PlatformMath.s16(PlatformMath.s32(-(dx * camera.axis_x_12.z + dy * camera.axis_y_12.z)) >> 12))
	var axis_z: Vector3i = camera.axis_z_12
	var axis_x := Vector3i(
		PlatformMath.s16(PlatformMath.s32(axis_y.y * axis_z.z - axis_y.z * axis_z.y) >> 12),
		PlatformMath.s16(PlatformMath.s32(axis_y.z * axis_z.x - axis_y.x * axis_z.z) >> 12),
		PlatformMath.s16(PlatformMath.s32(axis_y.x * axis_z.y - axis_y.y * axis_z.x) >> 12))
	var rotation := PackedInt32Array([axis_x.x, axis_y.x, axis_z.x, axis_x.y, axis_y.y, axis_z.y, axis_x.z, axis_y.z, axis_z.z, 0, 0, 0])
	var offsets: Array[Vector3i] = []
	for point: Vector3i in [Vector3i(-128, -128, 0), Vector3i(128, -128, 0), Vector3i(-128, 128, 0), Vector3i(128, 128, 0)]:
		offsets.append(PlatformMath.apply(rotation, point))
	return offsets

static func _dot12(a: Vector3i, b: Vector3i) -> int:
	return PlatformMath.s32(a.x * b.x + a.y * b.y + a.z * b.z) >> 12

func _vertex(point: Vector3i, uv: Vector2) -> void:
	_sprites.surface_set_color(Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0))
	_sprites.surface_set_uv(uv)
	_sprites.surface_add_vertex(GameSpace.position(point.x, point.y, point.z))
