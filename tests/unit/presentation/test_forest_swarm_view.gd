extends GutTest
## Source sprite geometry and repeated drawing retain committed swarm state.

func test_swarm_sprite_faces_camera_with_forward_projected_into_its_plane() -> void:
	var camera := GameplayCameraSnapshot.new()
	var matrix: PackedInt32Array = EntityTransform.IDENTITY.duplicate()
	matrix[2] = 4096
	matrix[8] = 0
	var offsets: Array[Vector3i] = ForestSwarmView.sprite_offsets(matrix, camera)
	assert_eq(offsets, [Vector3i(128, -128, 0), Vector3i(128, 128, 0), Vector3i(-128, -128, 0), Vector3i(-128, 128, 0)])

func test_swarm_pointing_toward_camera_retains_source_degenerate_projection() -> void:
	var camera := GameplayCameraSnapshot.new()
	var offsets: Array[Vector3i] = ForestSwarmView.sprite_offsets(EntityTransform.IDENTITY, camera)
	assert_eq(offsets, [Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO])

func test_swarm_projection_does_not_normalize_a_shortened_axis() -> void:
	var camera := GameplayCameraSnapshot.new()
	var matrix: PackedInt32Array = EntityTransform.IDENTITY.duplicate()
	matrix[2] = 2048
	matrix[8] = 3547
	var offsets: Array[Vector3i] = ForestSwarmView.sprite_offsets(matrix, camera)
	assert_eq(offsets, [Vector3i(64, -64, 0), Vector3i(64, 64, 0), Vector3i(-64, -64, 0), Vector3i(-64, 64, 0)])

func test_drawing_is_inert_and_hidden_swarm_has_no_geometry() -> void:
	var view := ForestSwarmView.new()
	add_child_autofree(view)
	view._material = ModelShaders.material(null, ModelShaders.Blend.OPAQUE, false, true)
	var state := GameplayState.new()
	state.camera = GameplayCameraSnapshot.new()
	state.entities = EntityRunSnapshot.new()
	var entity := EntitySnapshot.new()
	entity.live = true
	entity.custom_state = EntityCustomState.new()
	entity.custom_state.swarm = EntitySwarmState.new()
	entity.custom_state.swarm.visible = true
	entity.custom_state.swarm.matrix12 = EntityTransform.IDENTITY.duplicate()
	entity.custom_state.swarm.matrix12[2] = 4096
	entity.custom_state.swarm.matrix12[8] = 0
	entity.custom_state.swarm.positions = [Vector3i(0, 0, 0), Vector3i(0, -64, 0), Vector3i(0, -128, 0)]
	state.entities.entities.append(entity)
	view.draw_state(state)
	assert_true(view.visible)
	assert_eq(view.mesh.get_surface_count(), 1)
	var drawn: Mesh = view.mesh
	view.draw_state(state)
	assert_same(view.mesh, drawn)
	assert_eq(entity.custom_state.swarm.positions, [Vector3i(0, 0, 0), Vector3i(0, -64, 0), Vector3i(0, -128, 0)])
	var hidden: GameplayState = state.copy()
	hidden.entities.entities[0].custom_state.swarm.visible = false
	view.draw_state(hidden)
	assert_false(view.visible)
	assert_eq(view.mesh.get_surface_count(), 0)
	view.clear()
	assert_null(view._state)
	assert_null(view._material)
