class_name CaveSpriteView
extends MeshInstance3D
## Draws firefly 3D sprites and pickup particle sprites from committed entity snapshots.
##
## Fireflies follow frozen ENTSTRCreateSprite (ENTITY.C:3164): an unlit MRCreate3DSprite
## in the entity's local XY plane, MR_SP3D_DEFAULT_SCALE (4<<16, MR_SPRT.H:80) and
## Animlist_fire_fly (ENTITY.C:85). Bonus flies and fat fire flies follow PGIN_pickup
## (PARTICLE.C:67): a screen-aligned glow quad under a screen-aligned image quad whose
## screen size is inversely proportional to depth, so constant world extents reproduce it.
## Animation phases use the committed tick because snapshots carry no creation tick.

## Resident English fixed and generic banks holding firefly, pickup and glow images, in load order.
const RESIDENT_BANKS: PackedStringArray = ["FIXE_VRAM.VLO", "GEN_VRAM.VLO"]
## Firefly anim-list images, resolved by FrogLord name.
const FIREFLY_IMAGES: PackedStringArray = ["fire_fly", "fire_flya"]
## Default 16.16 3D sprite scale of MRCreate3DSprite.
const SPRITE_3D_SCALE: int = 4 << 16
## Pickup row hard-coded by ENTSTRCavCreateFatFireFly (GEN_FAT_FIRE_FLY).
const FAT_FIRE_FLY_PICKUP: int = 9
## Retail PC PGIN_pickup glow image (bmp_pointers[1727]); the PSX source names im_tongue_tip.
const GLOW_TEXTURE_ID: int = 1727
## Source units the glow sits behind its image so depth testing keeps the image on top.
const GLOW_DEPTH: float = 4.0
## Game units pickup glow and image depth moves toward the camera: PICKUP_OT_OFFSET
## (-16 ordering slots, PARTICLE.H) after the otz shift of 1 in Pickup_disp.
const PICKUP_DEPTH_BIAS: float = 32.0
## Firefly 3D sprites sort at their average corner depth with sc_ot_offset 0 (MR_SPRT.C).
const FIREFLY_DEPTH_BIAS: float = 0.0
## PGEN horizontal divisor: 256 (Pickup_disp shift) times focal 512 over otz shift 1.
const PICKUP_DIVISOR_X: float = 65536.0
## PGEN vertical divisor: 256 times the Windows vertical focal 480 over otz shift 1.
const PICKUP_DIVISOR_Y: float = 61440.0

## One prepared image material with its source pixel dimensions.
class Sprite extends RefCounted:
	var material: ShaderMaterial
	var width: int = 0
	var height: int = 0

	func _init(sprite_material: ShaderMaterial, sprite_width: int, sprite_height: int) -> void:
		material = sprite_material
		width = sprite_width
		height = sprite_height

## Prepared frames, 16.16 sprite size and glow colour of one pickup table row.
class PickupLook extends RefCounted:
	var frames: Array[Sprite] = []
	var size: int = 0
	var glow := Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0)

## Accumulated triangle corners and colours of one material.
class Batch extends RefCounted:
	var positions := PackedVector3Array()
	var colours := PackedColorArray()

var _sprites := ImmediateMesh.new()
var _firefly: Array[Sprite] = []
var _pickups: Dictionary[int, PickupLook] = {}
var _glow: Sprite = null
var _materials: Array[ShaderMaterial] = []
var _resident: TextureLibrary = null
var _projection_scale := Vector2.ONE
var _state: GameplayState

## Resolves the images the supplied definitions draw; missing images are returned as diagnostics.
func configure(scene: MapSceneData, data: AssetCatalog, definitions: Array[EntityDefinition]) -> String:
	clear()
	if scene == null or data == null or data.tables == null:
		return "Cave sprites require player texture banks and executable tables"
	var problems := PackedStringArray()
	_load_resident(data, problems)
	var firefly: bool = false
	var types: Dictionary[int, bool] = {}
	for definition: EntityDefinition in definitions:
		if definition == null or definition.behavior == null:
			continue
		match definition.behavior.kind:
			EntityBehavior.Kind.FIREFLY:
				firefly = true
			EntityBehavior.Kind.FAT_FIRE_FLY:
				types[FAT_FIRE_FLY_PICKUP] = true
			EntityBehavior.Kind.PICKUP:
				types[definition.pickup_type] = true
	if firefly:
		_configure_firefly(scene, data, problems)
	if not types.is_empty():
		_configure_pickups(scene, data, types.keys(), problems)
	_resident = null
	return "; ".join(problems)

## Releases prepared materials and any retained snapshot.
func clear() -> void:
	_state = null
	_firefly.clear()
	_pickups.clear()
	_glow = null
	_resident = null
	_materials.clear()
	_sprites.clear_surfaces()
	visible = false

## Applies the same source projection correction as terrain and models.
func set_projection_scale(scale: Vector2) -> void:
	_projection_scale = scale
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("projection_scale", scale)

## Rebuilds sprites only for a new committed state; repeated rendering is inert.
func draw_state(state: GameplayState, definitions: Array[EntityDefinition]) -> void:
	if state == _state:
		return
	_state = state
	_sprites.clear_surfaces()
	visible = false
	if state == null or state.entities == null:
		return
	var batches: Dictionary[ShaderMaterial, Batch] = {}
	for slot: int in mini(definitions.size(), state.entities.entities.size()):
		var definition: EntityDefinition = definitions[slot]
		var entity: EntitySnapshot = state.entities.entities[slot]
		if definition == null or definition.behavior == null or not shown(entity):
			continue
		match definition.behavior.kind:
			EntityBehavior.Kind.FIREFLY:
				_add_firefly(batches, entity, state.tick_index)
			EntityBehavior.Kind.FAT_FIRE_FLY:
				_add_pickup(batches, entity, FAT_FIRE_FLY_PICKUP, state)
			EntityBehavior.Kind.PICKUP:
				_add_pickup(batches, entity, definition.pickup_type, state)
	if batches.is_empty():
		return
	for material: ShaderMaterial in batches:
		var batch: Batch = batches[material]
		_sprites.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
		for index: int in batch.positions.size():
			_sprites.surface_set_color(batch.colours[index])
			_sprites.surface_set_uv(_corner_uv(index % 6))
			_sprites.surface_add_vertex(batch.positions[index])
		_sprites.surface_end()
	mesh = _sprites
	visible = true

## Model visibility rule shared with entity meshes: live, displayed and not hidden.
static func shown(entity: EntitySnapshot) -> bool:
	return entity.live and not entity.pop_allocated and not bool(entity.entity_flags & (EntityDefinition.HIDDEN | EntityDefinition.NO_DISPLAY)) and (entity.custom_state == null or not entity.custom_state.model_hidden)

## Firefly anim-list image after a sprite's age in updates, its creation update being age 0.
##
## MRProcessSpriteAnim (MR_SPRT.C:975) starts with count 1, so the creation update runs
## SETSPEED 2, SETCOUNT 0 and SETIMAGE fire_fly; every later image (LOOPBACK included)
## executes when the reloaded count of 2 expires, holding each image for two updates.
static func frame_index(age: int) -> int:
	return (maxi(0, age) >> 1) & 1

## Pickup image index: Pickup_move advances on alternate frames and wraps at the list end.
static func pickup_frame(age: int, count: int) -> int:
	return (maxi(0, age) >> 1) % count if count > 0 else 0

## 16.16 glow magnitude after a pickup's age in updates ([GlowPulse]).
static func glow_magnitude(age: int) -> int:
	return GlowPulse.magnitude(GlowPulse.angle_after(age))

## Source half extents of a default-scale 3D sprite image (MR_SPRT.C:706-707).
static func sprite_half_extents(width: int, height: int) -> Vector2i:
	return Vector2i((((width * SPRITE_3D_SCALE) >> 16) & 0xffff) >> 1, (((height * SPRITE_3D_SCALE) >> 16) & 0xffff) >> 1)

## World half extents equivalent to a PGEN quad of image size times a 16.16 magnitude.
static func pickup_half_extents(width: int, height: int, magnitude: int) -> Vector2:
	return Vector2(width * magnitude / PICKUP_DIVISOR_X, height * magnitude / PICKUP_DIVISOR_Y)

## Entity-local XY corner offsets of a 3D sprite in source order 0..3.
static func firefly_offsets(matrix12: PackedInt32Array, half: Vector2i) -> Array[Vector3i]:
	var offsets: Array[Vector3i] = []
	for point: Vector3i in [Vector3i(-half.x, -half.y, 0), Vector3i(half.x, -half.y, 0), Vector3i(-half.x, half.y, 0), Vector3i(half.x, half.y, 0)]:
		offsets.append(PlatformMath.apply(matrix12, point))
	return offsets

## Screen-aligned corner offsets in source order 0..3 from the committed camera axes.
static func screen_offsets(camera: GameplayCameraSnapshot, half: Vector2) -> Array[Vector3]:
	var axis_x: Vector3 = Vector3(camera.axis_x_12) * (half.x / 4096.0)
	var axis_y: Vector3 = Vector3(camera.axis_y_12) * (half.y / 4096.0)
	var offsets: Array[Vector3] = [-axis_x - axis_y, axis_x - axis_y, -axis_x + axis_y, axis_x + axis_y]
	return offsets

func _configure_firefly(scene: MapSceneData, data: AssetCatalog, problems: PackedStringArray) -> void:
	if data.names == null or data.names.images == null:
		problems.append("Cave firefly sprites require named player textures")
		return
	var frames: Array[Sprite] = []
	for image_name: String in FIREFLY_IMAGES:
		var image: VloImage = _image_for_id(scene, data.names.images.index_of(image_name))
		if image == null:
			problems.append("Cave firefly image %s is missing from the supplied banks" % image_name)
			continue
		var blend: ModelShaders.Blend = ModelShaders.blend_for_mode(image.blend_mode()) if image.has_flag(VloImage.FLAG_TRANSLUCENT) else ModelShaders.Blend.OPAQUE
		frames.append(_sprite(scene, image, blend, FIREFLY_DEPTH_BIAS))
	if frames.size() == FIREFLY_IMAGES.size():
		_firefly = frames

func _configure_pickups(scene: MapSceneData, data: AssetCatalog, types: Array, problems: PackedStringArray) -> void:
	var rows: Array[PickupData] = data.tables.pickups()
	var pointers: BmpPointers = data.tables.bmp_pointers()
	types.sort()
	for type: int in types:
		if type < 0 or type >= rows.size():
			problems.append("Pickup type %d has no pickup table row" % type)
			continue
		var row: PickupData = rows[type]
		var look := PickupLook.new()
		look.size = row.sprite_size
		look.glow = Color((row.glow_colour & 255) / 255.0, ((row.glow_colour >> 8) & 255) / 255.0, ((row.glow_colour >> 16) & 255) / 255.0)
		for pointer: int in row.frame_pointers:
			var image: VloImage = _image_for_id(scene, pointers.texture_id_for_pointer(pointer)) if pointers != null else null
			if image == null:
				problems.append("Pickup %s frame texture 0x%X is missing from the supplied banks" % [row.fly_type_name(), pointer])
				look.frames.clear()
				break
			look.frames.append(_sprite(scene, image, ModelShaders.Blend.OPAQUE, PICKUP_DEPTH_BIAS))
		if not look.frames.is_empty():
			_pickups[type] = look
	var glow: VloImage = _image_for_id(scene, GLOW_TEXTURE_ID)
	if glow == null:
		problems.append("Pickup glow texture %d is missing from the supplied banks" % GLOW_TEXTURE_ID)
	else:
		_glow = _sprite(scene, glow, ModelShaders.blend_for_mode(glow.blend_mode()), PICKUP_DEPTH_BIAS)

func _load_resident(data: AssetCatalog, problems: PackedStringArray) -> void:
	_resident = TextureLibrary.new()
	for bank_name: String in RESIDENT_BANKS:
		var entry: MwiEntry = data.find_resource(bank_name) if data.mwi != null else null
		if entry == null:
			problems.append("Sprite bank %s is missing" % bank_name)
			continue
		var bank: VloFile = data.read_texture_bank(entry.index, problems)
		if bank != null:
			_resident.add_bank(bank, bank_name)

func _image_for_id(scene: MapSceneData, identity: int) -> VloImage:
	if identity < 0:
		return null
	var image: VloImage = scene.library.image_for_id(identity, scene.preferred)
	if image == null and _resident != null:
		image = _resident.image_for_id(identity)
	return image

func _sprite(scene: MapSceneData, image: VloImage, blend: ModelShaders.Blend, depth_bias: float) -> Sprite:
	var material: ShaderMaterial = ModelShaders.material(scene.library.texture_for(image), blend, false, true)
	var uv: Rect2 = TextureBuilder.uv_rect(image)
	uv.size.x -= (1.0 / image.padded_width) if image.has_flag(VloImage.FLAG_HIT_X) else 0.0
	uv.size.y -= (1.0 / image.padded_height) if image.has_flag(VloImage.FLAG_HIT_Y) else 0.0
	material.set_shader_parameter("uv_scale", uv.size)
	material.set_shader_parameter("uv_offset", uv.position)
	material.set_shader_parameter("projection_scale", _projection_scale)
	material.set_shader_parameter("depth_bias", depth_bias)
	_materials.append(material)
	return Sprite.new(material, image.width, image.height)

func _add_firefly(batches: Dictionary[ShaderMaterial, Batch], entity: EntitySnapshot, tick: int) -> void:
	if _firefly.size() != FIREFLY_IMAGES.size():
		return
	var sprite: Sprite = _firefly[frame_index(tick)]
	var level: Vector3i = entity.colour_scale if entity.colour_scaled else Vector3i(128, 128, 128)
	var colour := Color(level.x / 255.0, level.y / 255.0, level.z / 255.0)
	var centre := Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
	var corners: Array[Vector3] = []
	for offset: Vector3i in firefly_offsets(entity.matrix12, sprite_half_extents(sprite.width, sprite.height)):
		var point: Vector3i = centre + offset
		corners.append(GameSpace.position(point.x, point.y, point.z))
	_add_quad(batches, sprite.material, corners, colour)

func _add_pickup(batches: Dictionary[ShaderMaterial, Batch], entity: EntitySnapshot, type: int, state: GameplayState) -> void:
	if state.camera == null or not _pickups.has(type):
		return
	var look: PickupLook = _pickups[type]
	var centre := Vector3(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
	if _glow != null:
		var behind: Vector3 = centre + Vector3(state.camera.axis_z_12) * (GLOW_DEPTH / 4096.0)
		var glow_half: Vector2 = pickup_half_extents(_glow.width, _glow.height, glow_magnitude(state.tick_index))
		_add_quad(batches, _glow.material, _screen_corners(behind, screen_offsets(state.camera, glow_half)), look.glow)
	var sprite: Sprite = look.frames[pickup_frame(state.tick_index, look.frames.size())]
	var half: Vector2 = pickup_half_extents(sprite.width, sprite.height, look.size)
	_add_quad(batches, sprite.material, _screen_corners(centre, screen_offsets(state.camera, half)), Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0))

func _screen_corners(centre: Vector3, offsets: Array[Vector3]) -> Array[Vector3]:
	var corners: Array[Vector3] = []
	for offset: Vector3 in offsets:
		var point: Vector3 = centre + offset
		corners.append(Vector3(point.x, -point.y, -point.z) / GameSpace.UNITS_PER_SQUARE)
	return corners

func _add_quad(batches: Dictionary[ShaderMaterial, Batch], material: ShaderMaterial, corners: Array[Vector3], colour: Color) -> void:
	if not batches.has(material):
		batches[material] = Batch.new()
	var batch: Batch = batches[material]
	for corner: int in [0, 1, 2, 2, 1, 3]:
		batch.positions.append(corners[corner])
		batch.colours.append(colour)

func _corner_uv(vertex: int) -> Vector2:
	match vertex:
		1, 4:
			return Vector2(1.0, 0.0)
		2, 3:
			return Vector2(0.0, 1.0)
		5:
			return Vector2(1.0, 1.0)
	return Vector2(0.0, 0.0)
