extends GutTest
## Source sprite rules and repeated drawing of committed firefly and pickup snapshots.

func test_firefly_anim_list_holds_each_image_for_two_updates() -> void:
	var frames: Array[int] = []
	for age: int in 9:
		frames.append(CaveSpriteView.frame_index(age))
	assert_eq(frames, [0, 0, 1, 1, 0, 0, 1, 1, 0])

func test_pickup_frames_advance_on_alternate_updates_and_wrap() -> void:
	var frames: Array[int] = []
	for age: int in 12:
		frames.append(CaveSpriteView.pickup_frame(age, 5))
	assert_eq(frames, [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 0, 0])
	assert_eq(CaveSpriteView.pickup_frame(7, 1), 0)

func test_sprite_extents_follow_source_scales() -> void:
	assert_eq(CaveSpriteView.sprite_half_extents(16, 10), Vector2i(32, 20), "default 3D scale 4<<16 halves to twice the image size")
	assert_eq(CaveSpriteView.pickup_half_extents(16, 15, 131072), Vector2(32.0, 32.0))
	assert_eq(CaveSpriteView.glow_magnitude(0), 0x3800 << 3)
	assert_eq(CaveSpriteView.glow_magnitude(4), (4096 + 0x3800) << 3)
	assert_eq(CaveSpriteView.glow_magnitude(16), 0x3800 << 3, "the pulse repeats every 16 updates")

func test_firefly_and_pickup_draw_one_quad_each_with_source_offsets() -> void:
	var view: CaveSpriteView = _view()
	var state: GameplayState = _state()
	var definitions: Array[EntityDefinition] = [_definition(EntityBehavior.Kind.FIREFLY), _definition(EntityBehavior.Kind.PICKUP, 3)]
	state.entities.entities.append(_entity(Vector3i(256, -64, 512)))
	state.entities.entities.append(_entity(Vector3i(-256, 0, 0)))
	view.draw_state(state, definitions)
	assert_true(view.visible)
	assert_eq(view.mesh.get_surface_count(), 2)
	var firefly: PackedVector3Array = view.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(firefly.size(), 6)
	assert_eq(firefly[0], GameSpace.position(256 - 32, -64 - 20, 512))
	assert_eq(firefly[1], GameSpace.position(256 + 32, -64 - 20, 512))
	assert_eq(firefly[5], GameSpace.position(256 + 32, -64 + 20, 512))
	var pickup: PackedVector3Array = view.mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
	assert_eq(pickup.size(), 6)
	assert_eq(pickup[0], GameSpace.position(-256 - 16, -16, 0))
	assert_eq(pickup[5], GameSpace.position(-256 + 16, 16, 0))
	var colours: PackedColorArray = view.mesh.surface_get_arrays(1)[Mesh.ARRAY_COLOR]
	assert_eq(colours[0], Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0))

func test_rotated_firefly_lies_in_its_entity_plane() -> void:
	var view: CaveSpriteView = _view()
	var state: GameplayState = _state()
	var entity: EntitySnapshot = _entity(Vector3i.ZERO)
	entity.matrix12 = PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 0, 0, 0])
	state.entities.entities.append(entity)
	view.draw_state(state, _definitions([_definition(EntityBehavior.Kind.FIREFLY)]))
	var firefly: PackedVector3Array = view.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(firefly[0], GameSpace.position(0, -20, 32))

func test_glow_sits_behind_image_with_table_colour() -> void:
	var view: CaveSpriteView = _view()
	var glow_material: ShaderMaterial = ModelShaders.material(null, ModelShaders.Blend.AVERAGE, false, true)
	view._glow = CaveSpriteView.Sprite.new(glow_material, 30, 30)
	var state: GameplayState = _state()
	state.entities.entities.append(_entity(Vector3i.ZERO))
	view.draw_state(state, _definitions([_definition(EntityBehavior.Kind.FAT_FIRE_FLY)]))
	assert_eq(view.mesh.get_surface_count(), 2)
	assert_same(view.mesh.surface_get_material(0), glow_material)
	var glow: PackedVector3Array = view.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var half: Vector2 = CaveSpriteView.pickup_half_extents(30, 30, CaveSpriteView.glow_magnitude(state.tick_index))
	assert_almost_eq(glow[0], Vector3(-half.x, half.y, -CaveSpriteView.GLOW_DEPTH) / 256.0, Vector3.ONE * 0.00001)
	var colours: PackedColorArray = view.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_eq(colours[0], Color(0x84 / 255.0, 0x84 / 255.0, 0x50 / 255.0))

func test_firefly_colour_follows_applied_scale_and_pickup_image_stays_neutral() -> void:
	var view: CaveSpriteView = _view()
	var state: GameplayState = _state()
	var firefly: EntitySnapshot = _entity(Vector3i.ZERO)
	firefly.colour_scaled = true
	firefly.colour_scale = Vector3i(64, 32, 0)
	var pickup: EntitySnapshot = _entity(Vector3i.ZERO)
	pickup.colour_scaled = true
	pickup.colour_scale = Vector3i.ZERO
	state.entities.entities.append(firefly)
	state.entities.entities.append(pickup)
	view.draw_state(state, _definitions([_definition(EntityBehavior.Kind.FIREFLY), _definition(EntityBehavior.Kind.PICKUP, 3)]))
	var colours: PackedColorArray = view.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_eq(colours[0], Color(64 / 255.0, 32 / 255.0, 0.0))
	colours = view.mesh.surface_get_arrays(1)[Mesh.ARRAY_COLOR]
	assert_eq(colours[0], Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0), "PGEN images never read a base colour")
	var black: GameplayState = state.copy()
	black.entities.entities[0].colour_scale = Vector3i.ZERO
	view.draw_state(black, _definitions([_definition(EntityBehavior.Kind.FIREFLY)]))
	colours = view.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_eq(colours[0], Color(0.0, 0.0, 0.0), "an applied zero scale draws black")

func test_animation_frame_follows_committed_tick() -> void:
	var view: CaveSpriteView = _view()
	var state: GameplayState = _state()
	state.tick_index = 2
	state.entities.entities.append(_entity(Vector3i.ZERO))
	view.draw_state(state, _definitions([_definition(EntityBehavior.Kind.FIREFLY)]))
	assert_same(view.mesh.surface_get_material(0), view._firefly[1].material)

func test_drawing_is_inert_and_hidden_entities_have_no_geometry() -> void:
	var view: CaveSpriteView = _view()
	var state: GameplayState = _state()
	state.entities.entities.append(_entity(Vector3i.ZERO))
	var definitions: Array[EntityDefinition] = [_definition(EntityBehavior.Kind.PICKUP, 3)]
	view.draw_state(state, definitions)
	var drawn: Mesh = view.mesh
	view.draw_state(state, definitions)
	assert_same(view.mesh, drawn)
	assert_eq(view.mesh.get_surface_count(), 1)
	for change: Callable in [
			func(entity: EntitySnapshot) -> void: entity.live = false,
			func(entity: EntitySnapshot) -> void: entity.entity_flags = EntityDefinition.HIDDEN,
			func(entity: EntitySnapshot) -> void: entity.entity_flags = EntityDefinition.NO_DISPLAY,
			func(entity: EntitySnapshot) -> void: entity.pop_allocated = true,
			func(entity: EntitySnapshot) -> void: entity.custom_state.model_hidden = true]:
		var hidden: GameplayState = state.copy()
		change.call(hidden.entities.entities[0])
		view.draw_state(hidden, definitions)
		assert_false(view.visible)
		assert_eq(view.mesh.get_surface_count(), 0)
	view.clear()
	assert_null(view._state)
	assert_true(view._pickups.is_empty())

func test_missing_images_return_diagnostics_and_draw_nothing() -> void:
	var view := CaveSpriteView.new()
	add_child_autofree(view)
	var definitions: Array[EntityDefinition] = [_definition(EntityBehavior.Kind.FIREFLY), _definition(EntityBehavior.Kind.PICKUP, 3)]
	assert_string_contains(view.configure(null, null, definitions), "require")
	var lists := GameNameLists.new()
	lists.images = NameBank.new()
	lists.images.names = PackedStringArray(["fire_fly", "fire_flya"])
	var row := PickupData.new()
	row.fly_type = 3
	row.sprite_size = 65536
	row.frame_pointers = PackedInt64Array([0x401000])
	var rows: Array[PickupData] = [row, row, row, row]
	var data := AssetCatalog.new()
	data.tables = GameTables.new()
	data.tables.pickup_table = rows
	data.tables.bmp_pointer_table = BmpPointers.new()
	data.names = lists
	var issue: String = view.configure(MapSceneData.new(), data, definitions)
	assert_string_contains(issue, "fire_fly is missing")
	assert_string_contains(issue, "fire_flya is missing")
	assert_string_contains(issue, "SCORE_100 frame texture 0x401000 is missing")
	assert_string_contains(issue, "glow texture 1727 is missing")
	var state: GameplayState = _state()
	state.entities.entities.append(_entity(Vector3i.ZERO))
	state.entities.entities.append(_entity(Vector3i.ZERO))
	view.draw_state(state, definitions)
	assert_false(view.visible)

func test_images_absent_from_scene_banks_resolve_from_resident_banks() -> void:
	var view := CaveSpriteView.new()
	add_child_autofree(view)
	var pixels: Array[int] = []
	for _index: int in 10 * 6:
		pixels.append_array([200, 120, 40])
	var resident: VloFile = SyntheticVlo.bank([SyntheticVlo.spec(8, 4, 2, 40, 0, SyntheticVlo.abgr(pixels))])
	var scene := MapSceneData.new()
	assert_null(view._image_for_id(scene, 40))
	view._resident = TextureLibrary.new()
	view._resident.add_bank(resident, "GEN_VRAM.VLO")
	assert_same(view._image_for_id(scene, 40), resident.find_texture(40))
	assert_null(view._image_for_id(scene, -1))

func _view() -> CaveSpriteView:
	var view := CaveSpriteView.new()
	add_child_autofree(view)
	var firefly_a: ShaderMaterial = ModelShaders.material(null, ModelShaders.Blend.OPAQUE, false, true)
	var firefly_b: ShaderMaterial = ModelShaders.material(null, ModelShaders.Blend.OPAQUE, false, true)
	view._firefly = [CaveSpriteView.Sprite.new(firefly_a, 16, 10), CaveSpriteView.Sprite.new(firefly_b, 16, 10)]
	for type: int in [3, CaveSpriteView.FAT_FIRE_FLY_PICKUP]:
		var look := CaveSpriteView.PickupLook.new()
		look.size = 65536
		look.glow = Color(0x84 / 255.0, 0x84 / 255.0, 0x50 / 255.0)
		look.frames = [CaveSpriteView.Sprite.new(ModelShaders.material(null, ModelShaders.Blend.OPAQUE, false, true), 16, 15)]
		view._pickups[type] = look
	return view

func _definitions(list: Array) -> Array[EntityDefinition]:
	var typed: Array[EntityDefinition] = []
	typed.assign(list)
	return typed

func _state() -> GameplayState:
	var state := GameplayState.new()
	state.camera = GameplayCameraSnapshot.new()
	state.entities = EntityRunSnapshot.new()
	return state

func _definition(kind: EntityBehavior.Kind, pickup_type: int = 0) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.behavior.kind = kind
	definition.pickup_type = pickup_type
	return definition

func _entity(at: Vector3i) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.live = true
	entity.custom_state = EntityCustomState.new()
	entity.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, at.x, at.y, at.z])
	return entity
