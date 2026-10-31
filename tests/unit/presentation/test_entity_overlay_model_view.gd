extends GutTest
## Overlay flipbooks follow committed overlay snapshots at identity rotation and are inert to redraws.

func test_only_desert_rocks_use_overlays() -> void:
	assert_true(EntityOverlayModelView.uses_overlay(EntityBehavior.Kind.DES_FALLING_ROCK))
	assert_true(EntityOverlayModelView.uses_overlay(EntityBehavior.Kind.DES_ROLLING_ROCK))
	assert_false(EntityOverlayModelView.uses_overlay(EntityBehavior.Kind.PATH_FOLLOWER))
	assert_false(EntityOverlayModelView.uses_overlay(EntityBehavior.Kind.FIREFLY))

func test_overlay_shows_only_while_published() -> void:
	var view: EntityOverlayModelView = _view()
	var state: GameplayState = _state()
	state.entities.entities.append(_entity(Vector3i(512, -128, 1024), null))
	view.draw_state(state)
	assert_eq(view.shown_count(), 0)
	assert_eq(view.get_child_count(), 0, "no instance exists before an overlay is published")
	var exploding: GameplayState = _state()
	exploding.entities.entities.append(_entity(Vector3i(512, -128, 1024), _overlay(0, 1)))
	view.draw_state(exploding)
	assert_eq(view.shown_count(), 1)
	assert_true(view._instances[0].visible)
	var settled: GameplayState = _state()
	settled.entities.entities.append(_entity(Vector3i(512, -128, 1024), null))
	view.draw_state(settled)
	assert_eq(view.shown_count(), 0)
	assert_false(view._instances[0].visible)

func test_overlay_uses_identity_rotation_at_published_position() -> void:
	var view: EntityOverlayModelView = _view()
	var state: GameplayState = _state()
	var entity: EntitySnapshot = _entity(Vector3i(768, -256, 2048), _overlay(0, 0))
	entity.matrix12 = PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 10, 20, 30])
	state.entities.entities.append(_entity(Vector3i.ZERO, null))
	state.entities.entities.append(entity)
	view.draw_state(state)
	var instance: AnimatedModelInstance = view._instances[1]
	assert_eq(instance.transform, Transform3D(Basis.IDENTITY, GameSpace.position(768, -256, 2048)))
	assert_eq(instance.transform, EntityOverlayModelView.overlay_transform(Vector3i(768, -256, 2048)))
	assert_eq(view.shown_count(), 1)

func test_frame_follows_committed_cel_with_clamping() -> void:
	var view: EntityOverlayModelView = _view()
	var cels: Array[int] = []
	for cel: int in [-1, 0, 1, 2, 9]:
		var state: GameplayState = _state()
		state.entities.entities.append(_entity(Vector3i.ZERO, _overlay(0, cel)))
		view.draw_state(state)
		var instance: AnimatedModelInstance = view._instances[0]
		cels.append(instance.player.frame)
		assert_eq(instance._current.partcels[0], instance.player.frame, "the sampled pose shows the selected cel")
	assert_eq(cels, [0, 0, 1, 2, 2])

func test_drawing_is_inert_and_never_changes_snapshots() -> void:
	var view: EntityOverlayModelView = _view()
	var state: GameplayState = _state()
	var overlay: EntityAnimationState = _overlay(0, 1)
	state.entities.entities.append(_entity(Vector3i(256, 0, 0), overlay))
	view.draw_state(state)
	var instance: AnimatedModelInstance = view._instances[0]
	var tick: int = instance.player.tick
	view.draw_state(state, 0.5)
	view.draw_state(state, 1.0)
	assert_same(view._instances[0], instance)
	assert_eq(instance.player.tick, tick, "drawing never advances the overlay clock")
	assert_eq(instance.player.frame, 1)
	assert_eq(overlay.cel, 1)
	assert_eq(overlay.action, 0)
	assert_eq(state.entities.entities[0].custom_state.overlay_position, Vector3i(256, 0, 0))

func test_dead_entities_hide_their_overlay() -> void:
	var view: EntityOverlayModelView = _view()
	var state: GameplayState = _state()
	state.entities.entities.append(_entity(Vector3i.ZERO, _overlay(0, 0)))
	view.draw_state(state)
	assert_eq(view.shown_count(), 1)
	var dead: GameplayState = state.copy()
	dead.entities.entities[0].live = false
	view.draw_state(dead)
	assert_eq(view.shown_count(), 0)

func test_clear_releases_instances_and_model() -> void:
	var view: EntityOverlayModelView = _view()
	var state: GameplayState = _state()
	state.entities.entities.append(_entity(Vector3i.ZERO, _overlay(0, 0)))
	view.draw_state(state)
	assert_eq(view.get_child_count(), 1)
	view.clear()
	assert_eq(view.get_child_count(), 0)
	assert_true(view._instances.is_empty())
	assert_null(view._state)
	assert_false(view.is_configured())
	view.draw_state(state)
	assert_eq(view.shown_count(), 0)

func test_missing_model_is_a_diagnostic_and_draws_nothing() -> void:
	var view := EntityOverlayModelView.new()
	add_child_autofree(view)
	assert_string_contains(view.configure(null, null), "could not be decoded")
	var file: MofFile = _flipbook(2)
	assert_string_contains(view.configure(file, null), "no drawable geometry")
	assert_false(view.is_configured())
	var state: GameplayState = _state()
	state.entities.entities.append(_entity(Vector3i.ZERO, _overlay(0, 0)))
	view.draw_state(state)
	assert_eq(view.get_child_count(), 0)

func test_projection_scale_reaches_shared_materials() -> void:
	var view: EntityOverlayModelView = _view()
	view.set_projection_scale(Vector2(0.5, 2.0))
	var material: ShaderMaterial = view._mesh.part_meshes[0].surface_get_material(0) as ShaderMaterial
	var scale: Vector2 = material.get_shader_parameter("projection_scale")
	assert_eq(scale, Vector2(0.5, 2.0))

func _view() -> EntityOverlayModelView:
	var view := EntityOverlayModelView.new()
	add_child_autofree(view)
	var file: MofFile = _flipbook(3)
	var mesh: ModelMesh = ModelMeshBuilder.new(TextureLibrary.new()).build_animated(file)
	assert_eq(view.configure(file, mesh), "")
	return view

func _flipbook(cels: int) -> MofFile:
	var file: MofFile = SyntheticMof.static_file([SyntheticMof.square(MofPolygonType.F4)])
	var part: MofPart = file.static_models[0].parts[0]
	for index: int in range(1, cels):
		var cel := MofPart.Partcel.new()
		cel.vertices = part.partcels[0].vertices.duplicate()
		cel.normals = part.partcels[0].normals.duplicate()
		for at: int in range(0, cel.vertices.size(), 3):
			cel.vertices[at] += 256 * index
		part.partcels.append(cel)
	part.partcel_count = cels
	var action := MofPart.FlipbookAction.new()
	action.start = 0
	action.frame_count = cels
	part.flipbook_actions.append(action)
	return file

func _overlay(action: int, cel: int) -> EntityAnimationState:
	var overlay: EntityAnimationState = EntityAnimationState.create(PackedInt32Array([3]), true)
	overlay.action = action
	overlay.cel = cel
	return overlay

func _state() -> GameplayState:
	var state := GameplayState.new()
	state.camera = GameplayCameraSnapshot.new()
	state.entities = EntityRunSnapshot.new()
	return state

func _entity(overlay_at: Vector3i, overlay: EntityAnimationState) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.live = true
	entity.custom_state = EntityCustomState.new()
	entity.custom_state.overlay_animation = overlay
	entity.custom_state.overlay_position = overlay_at
	entity.custom_state.model_hidden = overlay != null
	return entity
