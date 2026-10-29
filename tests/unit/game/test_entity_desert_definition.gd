extends GutTest
## Desert definition ownership and the shared animation and transform helpers its behaviors use.

func test_definition_copy_detaches_desert_operands() -> void:
	var definition := EntityDefinition.new()
	definition.desert = EntityDesertDefinition.new()
	definition.desert.rock_targets.append(Vector3i(1, 2, 3))
	definition.desert.rock_times.append(30)
	definition.desert.explosion_action_lengths.append(8)
	definition.desert.rise_height = 512
	var copied: EntityDefinition = definition.copy()
	assert_ne(copied.desert, definition.desert)
	definition.desert.rock_targets[0] = Vector3i.ZERO
	definition.desert.rock_times[0] = 1
	definition.desert.explosion_action_lengths[0] = 1
	assert_eq(copied.desert.rock_targets[0], Vector3i(1, 2, 3))
	assert_eq(copied.desert.rock_times, PackedInt32Array([30]))
	assert_eq(copied.desert.explosion_action_lengths, PackedInt32Array([8]))
	assert_eq(copied.desert.rise_height, 512)
	assert_null(EntityDefinition.new().copy().desert)

func test_custom_state_copy_deep_copies_the_overlay_animation() -> void:
	var state := EntityCustomState.new()
	assert_eq(state.requested_action, -1)
	assert_false(state.shadow_visible)
	assert_false(state.deadly)
	state.overlay_animation = EntityAnimationState.create(PackedInt32Array([4]), true)
	state.overlay_position = Vector3i(1, -2, 3)
	state.requested_action = 2
	state.shadow_visible = true
	state.deadly = true
	var copied: EntityCustomState = state.copy()
	state.overlay_animation.advance()
	assert_ne(copied.overlay_animation, state.overlay_animation)
	assert_eq(copied.overlay_animation.cel, -1)
	assert_true(copied.overlay_animation.one_shot)
	assert_eq([copied.overlay_position, copied.requested_action, copied.shadow_visible, copied.deadly], [Vector3i(1, -2, 3), 2, true, true])

func test_animation_finishes_on_the_last_cel_of_a_valid_action() -> void:
	var animation: EntityAnimationState = EntityAnimationState.create(PackedInt32Array([3, 1]))
	assert_false(animation.finished())
	animation.advance()
	animation.advance()
	assert_false(animation.finished())
	animation.advance()
	assert_true(animation.finished())
	animation.select(1)
	assert_false(animation.finished())
	animation.advance()
	assert_true(animation.finished())
	animation.action = 2
	assert_false(animation.finished())
	assert_false(EntityAnimationState.create(PackedInt32Array()).finished())

func test_forward_matrix_normalises_then_crosses_with_world_y() -> void:
	assert_eq(EntityTransform.from_forward(Vector3i(0, 0, 9)), EntityTransform.IDENTITY)
	assert_eq(EntityTransform.from_forward(Vector3i(3, 0, 4)), PackedInt32Array([3277, 0, 2458, 0, 4096, 0, -2458, 0, 3277, 0, 0, 0]))
	assert_eq(EntityTransform.from_forward(Vector3i(0, -4096, 4096)), PackedInt32Array([4096, 0, 0, 0, 2896, -2896, 0, 2896, 2896, 0, 0, 0]))
	assert_eq(EntityTransform.from_forward(Vector3i(300, -400, 0)), PackedInt32Array([0, 3277, 2458, 0, 2458, -3277, -4096, 0, 0, 0, 0, 0]))
	assert_eq(EntityTransform.from_forward(Vector3i.ZERO), PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))

func test_x_rotation_post_multiplies_and_keeps_translation() -> void:
	assert_eq(PlatformMath.x_rotation(-96), PackedInt32Array([4096, 0, 0, 0, 4052, 601, 0, -601, 4052, 0, 0, 0]))
	var moved: PackedInt32Array = EntityTransform.IDENTITY.duplicate()
	moved[9] = 1
	moved[10] = -2
	moved[11] = 3
	assert_eq(PlatformMath.rotate_x(moved, 1024), PackedInt32Array([4096, 0, 0, 0, 0, -4096, 0, 4096, 0, 1, -2, 3]))
	var tilted: PackedInt32Array = EntityTransform.from_forward(Vector3i(0, -4096, 4096))
	assert_eq(PlatformMath.rotate_x(tilted, 512), PackedInt32Array([4096, 0, 0, 0, 0, -4096, 0, 4095, 0, 0, 0, 0]))
