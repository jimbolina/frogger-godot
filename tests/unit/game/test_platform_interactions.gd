extends GutTest
## Single-player SAFE FORM attachment, movement, and transactional boundaries.

const SAFE: int = 1 | 2
const SOFT: int = 1 << 8
const ON_ENTITY: int = 1 << 2
const FROM_ENTITY: int = 1 << 4
const TO_ENTITY: int = 1 << 1

func _script(words: PackedInt32Array) -> EntityScriptDefinition:
	var program := EntityScriptDefinition.new()
	program.root_id = 1
	program.programs[1] = words
	program.names[1] = "SCRIPT_TURTLE"
	program.callbacks = {1: "SCRIPT_CB_LOG_SPLASH", 2: "SCRIPT_CB_DIVE_COLOUR_CHANGE"}
	return program

func test_script_callback_uses_previous_contact_and_late_guard_rolls_back() -> void:
	var level: LevelDefinition = _level()
	var entity: EntityDefinition = level.entity_collision.entities[0]
	entity.script_definition = _script([34, 0, 1, 0, 0, 11, 13, 0, 6, 2, 1, 12, 5])
	entity.script_definition.programs[2] = PackedInt32Array([38])
	entity.script_definition.names[2] = "SCRIPT_ORG_TRUCK_SFX"
	entity.action_lengths = PackedInt32Array([3, 4])
	level.exploration_guard = ExplorationGuard.new()
	level.exploration_guard.world_bounds = Rect2i(-129, -129, 2, 2)
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	var first: TickResult = _tick(run)
	assert_eq(first.error, "")
	assert_eq(first.final_snapshot.entity_hit_indices, PackedInt32Array([4]))
	assert_eq(first.final_snapshot.sound_requests, 0, "Same-tick hit must not call the script")
	var before: RunSnapshot = run.snapshot()
	var failed: TickResult = _tick(run)
	assert_string_contains(failed.error, "boundary")
	assert_null(failed.control_snapshot)
	assert_eq(failed.events, [])
	assert_eq(run.snapshot().rng_state, before.rng_state)
	assert_eq(run.snapshot().sound_requests, before.sound_requests)
	assert_eq(run.snapshot().entities.entities[0].script_state.timer, 1)
	assert_eq(run.snapshot().entities.entities[0].animation.cel, 0)
	assert_eq(run.reset(), "")
	assert_eq(run.snapshot().entities.entities[0].script_state.timer, 0)
	assert_eq(run.snapshot().entities.entities[0].animation.cel, -1)
	assert_eq(run.snapshot().rng_state, 1)
	level.exploration_guard = null
	run = TerrainRun.create(level)
	assert_eq(_tick(run).error, "")
	var second: TickResult = _tick(run)
	assert_eq(second.error, "")
	assert_true(second.events.has("entity:4:sound:19:0:0:0"))
	assert_eq(second.control_snapshot.sound_requests, 1)
	assert_eq(second.control_snapshot.entities.updates[0].previous_flags & 64, 64)
	assert_eq(second.control_snapshot.entities.updates[0].entity.requests, ["sound:19:0:0:0"])
	assert_eq(second.control_snapshot.entities.entities[0].live_flags & 1020, 0)
	assert_eq(second.final_snapshot.entities.entities[0].animation.cel, 1)

func test_ordered_scripts_share_rng_and_late_failure_discards_all_visits() -> void:
	var level: LevelDefinition = _level()
	_second_platform(level)
	for unused: int in FrogAnimationCatalog.ACTION_NAMES.size():
		level.frog_action_lengths.append(3)
	for entity: EntityDefinition in level.entity_collision.entities:
		entity.script_definition = _script([11, 13, 0, 6, 2, 1, 12, 5])
		entity.script_definition.programs[2] = PackedInt32Array([38])
		entity.script_definition.names[2] = "SCRIPT_ORG_TRUCK_SFX"
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	var initial: String = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
	run._animation.error = "forced post-script failure"
	var failed: TickResult = _tick(run)
	assert_eq(failed.error, "forced post-script failure")
	assert_null(failed.final_snapshot)
	assert_eq(run.snapshot().entities.updates.size(), 0)
	run._animation.error = ""
	assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), initial)
	var passed: TickResult = _tick(run)
	assert_eq(passed.error, "")
	var visits: Array[EntityUpdateObservation] = passed.control_snapshot.entities.updates
	assert_eq(visits.size(), 2)
	assert_eq(visits[0].entity.entity_index, 7)
	assert_eq(visits[1].entity.entity_index, 4)
	assert_eq(visits[0].rng_state, 1103527590)
	assert_eq(visits[1].rng_state, 2524885223)
	visits[0].entity.script_state.timer = 99
	assert_eq(run.snapshot().entities.updates[0].entity.script_state.timer, 1)

func test_diver_callback_death_reaches_same_control_phase() -> void:
	var level: LevelDefinition = _level()
	var entity: EntityDefinition = level.entity_collision.entities[0]
	entity.entity_name = "SUB_TURTLE"
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.start = Vector3i(-100, 0, -128)
	segment.end = Vector3i(-99, 0, -128)
	segment.length = 1
	entity.path_definition = PathDefinition.new()
	entity.path_definition.segments.append(segment)
	entity.path_start = PathStart.new()
	entity.path_start.speed = 0
	entity.path_start.flags = PathStart.REPEAT
	entity.script_definition = _script([34, 1, 2, 7, 1, 7, 0, 0, 0, 0, 1, 8, 0, 1, 128, 2048, -1, 9, 38])
	entity.action_lengths = PackedInt32Array([3, 4])
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	for tick: int in 16:
		var result: TickResult = _tick(run)
		assert_eq(result.error, "", str(tick))
		if not result.error.is_empty():
			return
		assert_ne(result.final_snapshot.mode, 2)
	var killed: TickResult = _tick(run)
	assert_eq(killed.error, "")
	assert_eq(killed.control_snapshot.mode, 2)
	assert_eq(killed.control_snapshot.death_equate, FrogAnimationCatalog.DROWN)
	assert_eq(killed.final_snapshot.entity_carry_indices, PackedInt32Array())
	assert_eq(killed.final_snapshot.entities.entities[0].script_state.colours, Vector3i(0, 64, 255))

func _level(width: int = 2) -> LevelDefinition:
	var level := LevelDefinition.new()
	level.grid = GridDefinition.new()
	level.grid.dimensions = Vector2i(2, 2)
	level.grid.base = Vector2i(-256, -256)
	level.spawn_cell = Vector2i.ZERO
	level.collision_enabled = true
	level.camera = GameplayCameraDefinition.new()
	for i: int in 4:
		var stack := GridStackDefinition.new()
		stack.first_square_index = i
		stack.square_count = 1
		level.grid.stacks.append(stack)
		var square := GridSquareDefinition.new()
		square.flags = 3
		var x: int = -256 + (i % 2) * 256
		@warning_ignore("integer_division")
		var z: int = -256 + (i / 2) * 256
		square.vertices.assign([Vector3i(x, 0, z + 256), Vector3i(x + 256, 0, z + 256),
			Vector3i(x, 0, z), Vector3i(x + 256, 0, z)])
		level.grid.squares.append(square)
	var entity := EntityDefinition.new()
	entity.entity_name = "STATIC"
	entity.entity_index = 4
	entity.unique_id = 7
	entity.form_grid_id = 2
	entity.form_id = 3
	entity.form_name = "PLATFORM"
	entity.matrix12[9] = -100
	entity.matrix12[11] = -128
	var contact := FormContactDefinition.new()
	contact.entity_index = entity.entity_index
	contact.unique_id = entity.unique_id
	contact.form_grid_id = entity.form_grid_id
	contact.form_id = entity.form_id
	contact.form_name = entity.form_name
	contact.dimensions = Vector2i(width, 1)
	contact.offsets = Vector2i(-128, -128)
	contact.height = 0
	contact.max_y = 64
	contact.radius_squared = 1000000
	for unused: int in width:
		contact.grid_flags.append(SAFE | SOFT)
	level.entity_collision = EntityCollisionDefinition.new()
	level.entity_collision.entities.append(entity)
	level.entity_collision.contacts.append(contact)
	level.entity_collision.group_base = Vector3i(-256, 0, -256)
	level.entity_collision.group_dimensions = Vector2i(2, 2)
	level.entity_collision.group_size = Vector2i(256, 256)
	level.entity_collision.platforms_enabled = true
	return level

func _tick(run: TerrainRun, pressed: int = 0, held: int = 0) -> TickResult:
	var command := TickCommand.new()
	command.tick_index = run.snapshot().tick_index
	command.pressed_mask = pressed
	command.held_mask = held
	return run.step(command)

func _second_platform(level: LevelDefinition) -> void:
	var entity: EntityDefinition = level.entity_collision.entities[0].copy()
	entity.entity_index = 7
	var contact: FormContactDefinition = level.entity_collision.contacts[0].copy()
	contact.entity_index = 7
	level.entity_collision.entities.append(entity)
	level.entity_collision.contacts.append(contact)

func test_safe_form_mount_centres_then_carries_without_recontact() -> void:
	var run: TerrainRun = TerrainRun.create(_level())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var first: TickResult = _tick(run)
	assert_eq(first.error, "")
	if not first.error.is_empty():
		return
	var mounted: RunSnapshot = first.final_snapshot
	assert_eq(mounted.current_entity_index, 4)
	assert_true(bool(mounted.flags & ON_ENTITY))
	assert_eq(mounted.entity_cell, Vector2i.ZERO)
	assert_eq(mounted.entity_offset_16, Vector3i(-28, 0, 0) * 65536)
	assert_eq(mounted.mode, 5)
	assert_eq(mounted.remaining_ticks, 2)
	assert_eq(mounted.entity_hit_indices, PackedInt32Array([4]))
	assert_eq(mounted.entity_carry_indices, PackedInt32Array([4]))
	assert_eq(first.entity_contacts.size(), 1)
	assert_eq(first.entity_contacts[0].status, FormReactionResult.SAFE)
	var middle: TickResult = _tick(run)
	assert_eq(middle.error, "")
	if not middle.error.is_empty():
		return
	assert_eq(middle.final_snapshot.entity_offset_16.x, -14 * 65536)
	assert_eq(middle.final_snapshot.current_entity_index, 4)
	assert_eq(middle.final_snapshot.entity_hit_indices.size(), 0)
	var complete: TickResult = _tick(run)
	assert_eq(complete.error, "")
	if not complete.error.is_empty():
		return
	assert_eq(complete.final_snapshot.mode, 0)
	assert_eq(complete.final_snapshot.entity_offset_16, Vector3i.ZERO)
	assert_eq(complete.final_snapshot.world_position, Vector3i(-100, 0, -128))
	assert_eq(complete.final_snapshot.current_entity_index, 4)
	assert_eq(complete.final_snapshot.entity_carry_indices, PackedInt32Array([4]))

func test_attached_hop_keeps_local_target_and_reacts_before_completion() -> void:
	var run: TerrainRun = TerrainRun.create(_level())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	for unused: int in 3:
		assert_eq(_tick(run).error, "")
	var started: TickResult = _tick(run, TickCommand.EAST)
	assert_eq(started.error, "")
	if not started.error.is_empty():
		return
	assert_eq(started.control_snapshot.mode, 1)
	assert_eq(started.control_snapshot.current_entity_index, 4)
	assert_true(bool(started.control_snapshot.flags & FROM_ENTITY))
	assert_true(bool(started.control_snapshot.flags & TO_ENTITY))
	assert_false(bool(started.control_snapshot.flags & ON_ENTITY))
	assert_eq(started.control_snapshot.entity_cell, Vector2i(1, 0))
	assert_eq(started.control_snapshot.remaining_ticks, 6)
	assert_eq(started.final_snapshot.remaining_ticks, 5)
	for unused: int in 3:
		assert_eq(_tick(run).error, "")
	var penultimate: TickResult = _tick(run)
	assert_eq(penultimate.error, "")
	if not penultimate.error.is_empty():
		return
	assert_eq(penultimate.final_snapshot.remaining_ticks, 1)
	assert_false(bool(penultimate.final_snapshot.flags & ON_ENTITY))
	assert_eq(penultimate.final_snapshot.entity_hit_indices, PackedInt32Array([4]))
	var completed: TickResult = _tick(run)
	assert_eq(completed.error, "")
	if not completed.error.is_empty():
		return
	assert_eq(completed.final_snapshot.remaining_ticks, 0)
	assert_true(bool(completed.final_snapshot.flags & ON_ENTITY))
	assert_eq(penultimate.final_snapshot.current_entity_index, 4)

func test_same_platform_usable_destination_reacts_without_safe_remount() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision.contacts[0].grid_flags[1] = 1
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	for unused: int in 3:
		assert_eq(_tick(run).error, "")
	var started: TickResult = _tick(run, TickCommand.EAST)
	assert_eq(started.error, "")
	if not started.error.is_empty():
		return
	for unused: int in 3:
		assert_eq(_tick(run).error, "")
	var count_one: TickResult = _tick(run)
	assert_eq(count_one.error, "")
	if not count_one.error.is_empty():
		return
	assert_eq(count_one.collision_snapshot.remaining_ticks, 1)
	assert_eq(count_one.entity_contacts.size(), 1)
	assert_eq(count_one.entity_contacts[0].status, FormReactionResult.HIT)
	assert_eq(count_one.collision_snapshot.entity_hit_indices, PackedInt32Array([4]))
	assert_eq(count_one.collision_snapshot.current_entity_index, 4)
	assert_false(count_one.events.has("platform_attachment"))
	var finished: TickResult = _tick(run)
	assert_eq(finished.error, "")
	if finished.error.is_empty():
		assert_true(bool(finished.final_snapshot.flags & ON_ENTITY))

func test_same_platform_pop_destination_kills_on_count_one() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision.contacts[0].grid_flags[1] = 1 | 4096
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	for unused: int in 3:
		assert_eq(_tick(run).error, "")
	assert_eq(_tick(run, TickCommand.EAST).error, "")
	for unused: int in 3:
		assert_eq(_tick(run).error, "")
	var count_one: TickResult = _tick(run)
	assert_eq(count_one.error, "")
	if not count_one.error.is_empty():
		return
	assert_eq(count_one.entity_contacts.size(), 1)
	assert_eq(count_one.entity_contacts[0].status, FormReactionResult.POP)
	assert_eq(count_one.collision_snapshot.death_entity_index, 4)
	assert_true(bool(count_one.collision_snapshot.flags & 8))
	assert_true(count_one.events.has("entity_pop_explosion_request"))

func test_vertical_same_platform_safe_rejection_still_marks_source_special_hit() -> void:
	var run: TerrainRun = TerrainRun.create(_level())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(_tick(run).error, "")
	var state: RunSnapshot = run.snapshot()
	state.flags = (state.flags & ~ON_ENTITY) | FROM_ENTITY | TO_ENTITY
	state.remaining_ticks = 1
	state.entities.entities[0].matrix12 = PackedInt32Array([4096, 0, 0, 0, 0, -4096, 0, 4096, 0, -100, 0, -128])
	var result := TickResult.new()
	assert_eq(run._contact_entities(state, result), "")
	assert_eq(result.entity_contacts.size(), 1)
	assert_eq(result.entity_contacts[0].status, FormReactionResult.NONE)
	assert_eq(result.entity_contacts[0].reason, "SAFE platform is too vertical")
	assert_true(result.entity_contacts[0].hit)
	assert_eq(state.entity_hit_indices, PackedInt32Array([4]))
	assert_eq(state.current_entity_index, 4)

func test_directional_input_interrupts_centring_before_countdown() -> void:
	var run: TerrainRun = TerrainRun.create(_level())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var mount: TickResult = _tick(run)
	assert_eq(mount.error, "")
	if not mount.error.is_empty():
		return
	assert_eq(mount.final_snapshot.mode, 5)
	assert_eq(mount.final_snapshot.remaining_ticks, 2)
	var hop: TickResult = _tick(run, TickCommand.EAST)
	assert_eq(hop.error, "")
	if not hop.error.is_empty():
		return
	assert_eq(hop.control_snapshot.mode, 1)
	assert_eq(hop.control_snapshot.remaining_ticks, 6)
	assert_eq(hop.control_snapshot.entity_cell, Vector2i(1, 0))
	assert_true(bool(hop.control_snapshot.flags & FROM_ENTITY))
	assert_true(bool(hop.control_snapshot.flags & TO_ENTITY))
	assert_eq(hop.move_snapshot.remaining_ticks, 5)

func test_unusable_form_tile_blocks_hop_without_departure() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision.contacts[0].grid_flags[1] = 0
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	for unused: int in 3:
		assert_eq(_tick(run).error, "")
	var blocked: TickResult = _tick(run, TickCommand.EAST)
	assert_eq(blocked.error, "")
	if not blocked.error.is_empty():
		return
	assert_eq(blocked.final_snapshot.current_entity_index, 4)
	assert_eq(blocked.final_snapshot.entity_cell, Vector2i.ZERO)
	assert_true(bool(blocked.final_snapshot.flags & ON_ENTITY))
	assert_false(bool(blocked.final_snapshot.flags & FROM_ENTITY))
	assert_eq(blocked.final_snapshot.mode, 0)
	assert_eq(blocked.final_snapshot.velocity_16, Vector3i.ZERO)
	assert_eq(blocked.final_snapshot.last_animation_request, FrogAnimationCatalog.OUCH)

func test_no_entity_angle_departs_through_world_grid() -> void:
	var level: LevelDefinition = _level(1)
	level.entity_collision.contacts[0].form_book_flags = 4
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	for unused: int in 3:
		assert_eq(_tick(run).error, "")
	var departed: TickResult = _tick(run, TickCommand.EAST)
	assert_eq(departed.error, "")
	if not departed.error.is_empty():
		return
	assert_eq(departed.control_snapshot.mode, 1)
	assert_eq(departed.control_snapshot.forbidden_entity_index, 4)
	assert_false(bool(departed.control_snapshot.flags & TO_ENTITY))
	assert_true(bool(departed.control_snapshot.flags & 64))
	assert_eq(departed.control_snapshot.cell, Vector2i(1, 0))
	for unused: int in 5:
		assert_eq(_tick(run).error, "")
	assert_eq(run.snapshot().current_entity_index, -1)
	assert_false(bool(run.snapshot().flags & ON_ENTITY))

func test_terrain_landing_can_remount_the_departed_platform_same_tick() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision.contacts[0].form_book_flags = 4
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	for unused: int in 3:
		assert_eq(_tick(run).error, "")
	assert_eq(_tick(run, TickCommand.EAST).error, "")
	for unused: int in 4:
		assert_eq(_tick(run).error, "")
	var landed: TickResult = _tick(run)
	assert_eq(landed.error, "")
	if not landed.error.is_empty():
		return
	assert_eq(landed.move_snapshot.current_entity_index, -1)
	assert_eq(landed.collision_snapshot.current_entity_index, 4)
	assert_eq(landed.final_snapshot.current_entity_index, 4)
	assert_eq(landed.final_snapshot.entity_carry_indices, PackedInt32Array([4]))

func test_no_centring_x_preserves_local_contact_x() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision.contacts[0].form_book_flags = 64
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var result: TickResult = _tick(run)
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.final_snapshot.current_entity_index, 4)
	assert_eq(result.final_snapshot.entity_offset_16.x, -28 * 65536)
	assert_eq(result.final_snapshot.target_16.x, -28 * 65536)
	assert_eq(result.final_snapshot.world_position.x, -128)

func test_no_centring_z_preserves_local_contact_z() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision.entities[0].matrix12[9] = -128
	level.entity_collision.entities[0].matrix12[11] = -100
	var contact: FormContactDefinition = level.entity_collision.contacts[0]
	contact.dimensions = Vector2i(1, 2)
	contact.form_book_flags = 128
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var result: TickResult = _tick(run)
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.final_snapshot.current_entity_index, 4)
	assert_eq(result.final_snapshot.entity_offset_16.z, -28 * 65536)
	assert_eq(result.final_snapshot.target_16.z, -28 * 65536)
	assert_eq(result.final_snapshot.world_position.z, -128)

func test_safe_precedes_pop_and_vertical_rejection_does_not_request_hit() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision.contacts[0].grid_flags[0] |= 4096
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var safe: TickResult = _tick(run)
	assert_eq(safe.error, "")
	if not safe.error.is_empty():
		return
	assert_eq(safe.final_snapshot.current_entity_index, 4)
	assert_eq(safe.final_snapshot.death_entity_index, -1)
	assert_false(safe.events.has("entity_pop_explosion_request"))
	level = _level()
	var matrix: PackedInt32Array = level.entity_collision.entities[0].matrix12
	matrix[0] = 0
	matrix[2] = 0
	matrix[6] = 4096
	matrix[8] = 0
	level.entity_collision.entities[0].matrix12 = matrix
	run = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var rejected: TickResult = _tick(run)
	assert_eq(rejected.error, "")
	if rejected.error.is_empty():
		assert_eq(rejected.entity_contacts.size(), 1)
		assert_eq(rejected.entity_contacts[0].reason, "SAFE platform is too vertical")
		assert_eq(rejected.final_snapshot.current_entity_index, -1)
		assert_eq(rejected.final_snapshot.entity_hit_indices.size(), 0)
		assert_eq(rejected.final_snapshot.entity_carry_indices.size(), 0)

func test_soft_and_nonsoft_fall_reactions_and_ascending_contact() -> void:
	for source_old_y: int in [-600, 600]:
		for soft: bool in [false, true]:
			var level: LevelDefinition = _level()
			if not soft:
				level.entity_collision.contacts[0].grid_flags[0] = SAFE
			var run: TerrainRun = TerrainRun.create(level)
			assert_eq(run.error, "")
			if not run.error.is_empty():
				continue
			run._state.old_y = source_old_y
			var contact: TickResult = _tick(run)
			assert_eq(contact.error, "")
			if not contact.error.is_empty():
				continue
			assert_eq(contact.final_snapshot.current_entity_index, 4)
			var should_stun: bool = source_old_y == -600 and not soft
			assert_eq(contact.events.has("stun_sound"), should_stun)
			assert_eq(contact.events.has("camera_stun_shake"), should_stun)
			assert_eq(contact.final_snapshot.sound_requests, 1 if should_stun else 0)
			assert_eq(contact.final_snapshot.rng_draw_count, 2 if should_stun else 0)

func test_safe_fall_boundaries_retain_source_reaction_thresholds() -> void:
	for fall_distance: int in [512, 513, 1024, 1025]:
		var level: LevelDefinition = _level()
		level.entity_collision.contacts[0].grid_flags[0] = SAFE
		var run: TerrainRun = TerrainRun.create(level)
		assert_eq(run.error, "")
		if not run.error.is_empty():
			continue
		run._state.old_y = -fall_distance
		var result: TickResult = _tick(run)
		assert_eq(result.error, "", "fall %d" % fall_distance)
		if not result.error.is_empty():
			continue
		assert_eq(result.collision_snapshot.current_entity_index, 4)
		assert_eq(result.events.has("pant"), fall_distance == 512)
		assert_eq(result.events.has("stun_sound"), fall_distance == 513 or fall_distance == 1024)
		assert_eq(result.collision_snapshot.sound_requests, 1 if fall_distance == 513 or fall_distance == 1024 else 0)
		assert_eq(result.events.has("camera_stun_shake"), fall_distance == 513 or fall_distance == 1024)
		assert_eq(bool(result.collision_snapshot.flags & 8), fall_distance == 1025)
		assert_eq(result.collision_snapshot.death_equate, 2 if fall_distance == 1025 else 0)

func test_ordered_safe_transfer_and_late_invalid_contact_rollback() -> void:
	var level: LevelDefinition = _level()
	_second_platform(level)
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var transferred: TickResult = _tick(run)
	assert_eq(transferred.error, "")
	if not transferred.error.is_empty():
		return
	assert_eq(transferred.final_snapshot.current_entity_index, 4)
	assert_eq(transferred.final_snapshot.entity_hit_indices, PackedInt32Array([7, 4]))
	assert_eq(transferred.final_snapshot.entity_carry_indices, PackedInt32Array([7, 4]))
	var transferred_again: TickResult = _tick(run)
	assert_eq(transferred_again.error, "")
	if transferred_again.error.is_empty():
		assert_eq(transferred_again.final_snapshot.current_entity_index, 4)
		assert_eq(transferred_again.final_snapshot.entity_hit_indices, PackedInt32Array([7, 4]),
			"current entity changes during the ordered scan, while candidates remain fixed")
	run = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	run._state.forbidden_entity_index = 7
	var forbidden: TickResult = _tick(run)
	assert_eq(forbidden.error, "")
	if forbidden.error.is_empty():
		assert_eq(forbidden.final_snapshot.entity_hit_indices, PackedInt32Array([4]))
		assert_eq(forbidden.final_snapshot.current_entity_index, 4)
	run = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	run._entity_collision.contacts[0].dimensions = Vector2i.ZERO
	var before: RunSnapshot = run.snapshot()
	var failed: TickResult = _tick(run)
	assert_false(failed.error.is_empty())
	assert_null(failed.final_snapshot)
	assert_eq(failed.entity_contacts.size(), 0)
	assert_eq(failed.events.size(), 0)
	assert_eq(run.snapshot().tick_index, before.tick_index)
	assert_eq(run.snapshot().current_entity_index, -1)
	assert_eq(run.snapshot().entity_carry_indices.size(), 0)
	run._entity_collision.contacts[0].dimensions = Vector2i(2, 1)
	assert_eq(_tick(run).error, "")

func test_source_order_allows_pop_after_safe_mount_in_same_pass() -> void:
	var level: LevelDefinition = _level()
	_second_platform(level)
	level.entity_collision.contacts[0].grid_flags[0] = 1 | 4096
	level.entity_collision.contacts[0].height = -64
	level.entity_collision.contacts[0].max_y = -1
	level.entity_collision.contacts[1].height = -32
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var result: TickResult = _tick(run)
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.entity_contacts.size(), 2)
	assert_eq(result.entity_contacts[0].status, FormReactionResult.SAFE)
	assert_eq(result.entity_contacts[1].status, FormReactionResult.POP)
	assert_eq(result.entity_contacts[0].contact.local_position.y, 0)
	assert_eq(result.entity_contacts[1].contact.local_position.y, -32,
		"later POP queries the frog after SAFE has lowered it")
	assert_eq(result.collision_snapshot.current_entity_index, 7)
	assert_eq(result.collision_snapshot.death_entity_index, 4)
	assert_eq(result.collision_snapshot.entity_hit_indices, PackedInt32Array([7, 4]))

func test_unsupported_same_platform_destination_rolls_back_whole_hop() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision.contacts[0].grid_flags[1] = 1 | 4
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	for unused: int in 3:
		assert_eq(_tick(run).error, "")
	var before: RunSnapshot = run.snapshot()
	var failed: TickResult = _tick(run, TickCommand.EAST)
	assert_string_contains(failed.error, "unsupported FORM reaction")
	assert_null(failed.control_snapshot)
	assert_null(failed.final_snapshot)
	assert_eq(failed.events.size(), 0)
	assert_eq(run.snapshot().tick_index, before.tick_index)
	assert_eq(run.snapshot().flags, before.flags)
	assert_eq(run.snapshot().entity_cell, before.entity_cell)
	assert_eq(run.snapshot().current_entity_index, before.current_entity_index)
	assert_eq(run.snapshot().camera.mod_matrix12, before.camera.mod_matrix12)

func test_form_wall_n_flag_allows_jump_off_instead_of_blocking() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision.contacts[0].grid_flags[1] = 16384
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	for unused: int in 3:
		assert_eq(_tick(run).error, "")
	var jumped: TickResult = _tick(run, TickCommand.EAST)
	assert_eq(jumped.error, "")
	if not jumped.error.is_empty():
		return
	assert_eq(jumped.control_snapshot.mode, 1)
	assert_true(bool(jumped.control_snapshot.flags & FROM_ENTITY))
	assert_false(bool(jumped.control_snapshot.flags & TO_ENTITY))
	assert_eq(jumped.control_snapshot.forbidden_entity_index, 4)

func test_quick_auto_and_super_hops_keep_source_requests() -> void:
	for powers: int in [0, 2, 4]:
		var level: LevelDefinition = _level()
		var start := RunStart.new()
		start.powerup_flags = powers
		start.quick_jump_timer = 10 if powers == 2 else 0
		start.auto_hop_timer = 10 if powers == 4 else 0
		var run: TerrainRun = TerrainRun.create(level, start)
		assert_eq(run.error, "")
		if not run.error.is_empty():
			continue
		for unused: int in 3:
			assert_eq(_tick(run).error, "")
		var hop: TickResult = _tick(run, 0 if powers == 4 else TickCommand.EAST,
			TickCommand.EAST if powers == 4 else 0)
		assert_eq(hop.error, "", "power %d" % powers)
		if not hop.error.is_empty():
			continue
		assert_eq(hop.control_snapshot.remaining_ticks, 3 if powers == 2 else 6)
		assert_eq(hop.control_snapshot.last_animation_request,
			FrogAnimationCatalog.SUPERHOP if powers == 2 else FrogAnimationCatalog.AUTOHOP if powers == 4 else FrogAnimationCatalog.HOP)
		assert_eq(hop.control_snapshot.score_requests, 0 if powers == 4 else 1)
		assert_eq(hop.control_snapshot.sound_requests, 1)
	var super_run: TerrainRun = TerrainRun.create(_level())
	assert_eq(super_run.error, "")
	if not super_run.error.is_empty():
		return
	for unused: int in 3:
		assert_eq(_tick(super_run).error, "")
	var super_hop: TickResult = _tick(super_run, TickCommand.SUPER_HOP)
	assert_eq(super_hop.error, "")
	if super_hop.error.is_empty():
		assert_eq(super_hop.control_snapshot.remaining_ticks, 15)
		assert_true(bool(super_hop.control_snapshot.flags & 32))
		assert_eq(super_hop.control_snapshot.last_animation_request, FrogAnimationCatalog.SUPERJUMP)
		assert_eq(super_hop.control_snapshot.score_requests, 1)
		assert_eq(super_hop.control_snapshot.sound_requests, 1)

func test_moving_platform_pose_precedes_carry() -> void:
	var level: LevelDefinition = _level(1)
	var entity: EntityDefinition = level.entity_collision.entities[0]
	entity.entity_name = "MOVING"
	entity.flags = EntityDefinition.ALIGN_TO_WORLD
	entity.path_definition = PathDefinition.new()
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 100
	segment.start = Vector3i(-100, 0, -138)
	segment.end = Vector3i(-100, 0, -38)
	entity.path_definition.segments.append(segment)
	entity.path_start = PathStart.new()
	entity.path_start.speed = 10
	level.entity_collision.contacts[0].entity_flags = entity.flags
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var mounted: TickResult = _tick(run)
	assert_eq(mounted.error, "")
	if not mounted.error.is_empty():
		return
	assert_eq(mounted.final_snapshot.entities.entities[0].matrix12[11], -128)
	assert_eq(mounted.final_snapshot.current_entity_index, 4)
	var offset_x: int = mounted.final_snapshot.entity_offset_16.x
	var carried: TickResult = _tick(run)
	assert_eq(carried.error, "")
	if not carried.error.is_empty():
		return
	assert_eq(carried.final_snapshot.entities.entities[0].matrix12[11], -118)
	assert_eq(carried.final_snapshot.current_entity_index, 4)
	assert_gt(carried.final_snapshot.entity_offset_16.x, offset_x)
	assert_eq(carried.final_snapshot.world_position.z, -118)

func test_carry_narrows_local_words_while_airborne_uses_full_fixed_fraction() -> void:
	var state := RunSnapshot.new()
	var pose := EntitySnapshot.new()
	state.entity_offset_16 = Vector3i(32768 * 65536, 0, 0)
	assert_eq(TerrainPlatform.carry(state, pose).error, "")
	assert_eq(state.position_16.x, -32768 * 65536)
	state.entity_offset_16 = Vector3i(-1, 0, 0)
	assert_eq(TerrainPlatform.carry(state, pose).error, "")
	assert_eq(state.position_16.x, -65536, "signed arithmetic shift before short narrowing")
	pose.matrix12 = PlatformMath.yaw(1024)
	state.entity_offset_16 = Vector3i(98304, 0, 0)
	assert_eq(TerrainPlatform.carry(state, pose).error, "")
	assert_eq(state.position_16.z, -65536, "carry discards the half-unit fraction")
	state.position_16 = Vector3i.ZERO
	state.velocity_16 = Vector3i.ZERO
	TerrainPlatform.airborne(state, pose)
	assert_eq(state.position_16.z, -98304, "airborne rotation retains full 16.16 fraction")

func test_platform_definitions_and_snapshots_are_detached() -> void:
	var level: LevelDefinition = _level()
	var copied: EntityCollisionDefinition = level.entity_collision.copy()
	assert_true(copied.platforms_enabled)
	copied.contacts[0].form_book_flags = 255
	copied.contacts[0].grid_flags[0] = 0
	assert_eq(level.entity_collision.contacts[0].form_book_flags, 0)
	assert_eq(level.entity_collision.contacts[0].grid_flags[0], SAFE | SOFT)
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(_tick(run).error, "")
	var detached: RunSnapshot = run.snapshot()
	detached.entity_transform12[0] = 0
	detached.entity_carry_indices.append(99)
	detached.camera.mod_matrix12[0] = 0
	assert_eq(run.snapshot().entity_transform12[0], 4096)
	assert_eq(run.snapshot().entity_carry_indices, PackedInt32Array([4]))
	assert_eq(run.snapshot().camera.mod_matrix12[0], 4096)

func test_failed_reset_preserves_attachment_and_successful_reset_clears_it() -> void:
	var run: TerrainRun = TerrainRun.create(_level())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(_tick(run).error, "")
	var before: RunSnapshot = run.snapshot()
	var invalid := RunStart.new()
	invalid.spawn_cell = Vector2i(99, 99)
	assert_false(run.reset(invalid).is_empty())
	var after: RunSnapshot = run.snapshot()
	assert_eq(after.tick_index, before.tick_index)
	assert_eq(after.current_entity_index, 4)
	assert_eq(after.entity_offset_16, before.entity_offset_16)
	assert_eq(after.entity_carry_indices, before.entity_carry_indices)
	assert_eq(after.camera.mod_matrix12, before.camera.mod_matrix12)
	assert_eq(run.reset(), "")
	assert_eq(run.snapshot().tick_index, 0)
	assert_eq(run.snapshot().current_entity_index, -1)
	assert_eq(run.snapshot().entity_carry_indices.size(), 0)
	assert_eq(run.snapshot().camera.mod_matrix12[0], 4096)

func test_late_animation_failure_rolls_back_mount_and_retry() -> void:
	var level: LevelDefinition = _level()
	for unused: int in FrogAnimationCatalog.ACTION_NAMES.size():
		level.frog_action_lengths.append(3)
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var before: RunSnapshot = run.snapshot()
	run._animation.error = "forced late failure"
	var failed: TickResult = _tick(run)
	assert_eq(failed.error, "forced late failure")
	assert_null(failed.final_snapshot)
	assert_eq(failed.entity_contacts.size(), 0)
	assert_eq(failed.events.size(), 0)
	assert_eq(run.snapshot().tick_index, before.tick_index)
	assert_eq(run.snapshot().current_entity_index, -1)
	assert_eq(run.snapshot().entity_carry_indices.size(), 0)
	run._animation.error = ""
	var succeeded: TickResult = _tick(run)
	assert_eq(succeeded.error, "")
	if succeeded.error.is_empty():
		assert_eq(succeeded.final_snapshot.current_entity_index, 4)
		assert_eq(succeeded.final_snapshot.entity_carry_indices, PackedInt32Array([4]))

func test_late_failures_rollback_carry_departure_and_transfer() -> void:
	var level: LevelDefinition = _level()
	for unused: int in FrogAnimationCatalog.ACTION_NAMES.size():
		level.frog_action_lengths.append(3)
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(_tick(run).error, "")
	var before_carry: RunSnapshot = run.snapshot()
	run._state.remaining_ticks = -1
	var failed_carry: TickResult = _tick(run)
	assert_string_contains(failed_carry.error, "Camera timers")
	assert_null(failed_carry.final_snapshot)
	assert_eq(failed_carry.events.size(), 0)
	assert_eq(run.snapshot().tick_index, before_carry.tick_index)
	assert_eq(run.snapshot().current_entity_index, 4)

	assert_eq(run.snapshot().entity_offset_16, before_carry.entity_offset_16)
	run._state.remaining_ticks = before_carry.remaining_ticks
	assert_eq(_tick(run).error, "")
	assert_eq(_tick(run).error, "")
	var before_departure: RunSnapshot = run.snapshot()
	run._animation.error = "forced departure failure"
	var failed_departure: TickResult = _tick(run, TickCommand.EAST)
	assert_eq(failed_departure.error, "forced departure failure")
	assert_null(failed_departure.final_snapshot)
	assert_eq(failed_departure.events.size(), 0)
	assert_eq(run.snapshot().tick_index, before_departure.tick_index)
	assert_eq(run.snapshot().current_entity_index, 4)
	assert_eq(run.snapshot().flags, before_departure.flags)
	assert_eq(run.snapshot().camera.mod_matrix12, before_departure.camera.mod_matrix12)
	run._animation.error = ""
	assert_eq(_tick(run, TickCommand.EAST).error, "")
	level = _level()
	_second_platform(level)
	for unused: int in FrogAnimationCatalog.ACTION_NAMES.size():
		level.frog_action_lengths.append(3)
	run = TerrainRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	run._animation.error = "forced transfer failure"
	var failed_transfer: TickResult = _tick(run)
	assert_eq(failed_transfer.error, "forced transfer failure")
	assert_null(failed_transfer.final_snapshot)
	assert_eq(failed_transfer.entity_contacts.size(), 0)
	assert_eq(run.snapshot().current_entity_index, -1)
	assert_eq(run.snapshot().entity_carry_indices.size(), 0)
	run._animation.error = ""
	assert_eq(_tick(run).error, "")
	assert_eq(run.snapshot().current_entity_index, 4)

func _guarded_mover() -> LevelDefinition:
	var level: LevelDefinition = _level()
	var entity: EntityDefinition = level.entity_collision.entities[0]
	entity.entity_name = "MOVING"
	entity.flags = EntityDefinition.ALIGN_TO_WORLD
	entity.path_definition = PathDefinition.new()
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 1000
	segment.start = Vector3i(-100, 0, -148)
	segment.end = Vector3i(-100, 0, 852)
	entity.path_definition.segments.append(segment)
	entity.path_start = PathStart.new()
	entity.path_start.speed = 20
	level.entity_collision.contacts[0].entity_flags = entity.flags
	level.exploration_guard = ExplorationGuard.new()
	level.exploration_guard.world_bounds = Rect2i(-512, -512, 1024, 1024)
	return level

func test_carry_guard_rejects_boundary_and_zone_without_advancing_paths() -> void:
	for active_zone: bool in [false, true]:
		var level: LevelDefinition = _guarded_mover()
		if active_zone:
			var zone := ZoneDefinition.new()
			zone.bounds = PackedInt32Array([0, 1, 0, 1])
			level.exploration_guard.zones.append(zone)
		else:
			level.exploration_guard.world_bounds = Rect2i(-512, -512, 1024, 392)
		var run: TerrainRun = TerrainRun.create(level)
		assert_eq(run.error, "")
		assert_eq(_tick(run).error, "")
		var failed: TickResult = null
		for unused: int in 10:
			var before: String = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
			var result: TickResult = _tick(run)
			if not result.error.is_empty():
				failed = result
				assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), before)
				break
		assert_not_null(failed)
		if failed != null:
			assert_string_contains(failed.error, "active camera zone" if active_zone else "Exploration boundary")
			assert_null(failed.final_snapshot)
			assert_true(failed.events.is_empty())
			assert_true(failed.entity_contacts.is_empty())
			assert_eq(run.snapshot().current_entity_index, 4)

func test_form_correction_guard_rolls_back_candidate_rng_outcomes_and_retry() -> void:
	var level: LevelDefinition = _level()
	level.entity_collision.entities[0].matrix12 = PackedInt32Array([4096, 0, 0, 0, 2896, -2896, 0, 2896, 2896, -100, 0, -128])
	level.entity_collision.contacts[0].height = -20
	level.entity_collision.contacts[0].grid_flags[0] = SAFE
	level.exploration_guard = ExplorationGuard.new()
	level.exploration_guard.world_bounds = Rect2i(-256, -130, 512, 386)
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	run._state.old_y = -600
	var before: String = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
	var failed: TickResult = _tick(run)
	assert_string_contains(failed.error, "Exploration boundary")
	assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), before)
	assert_null(failed.control_snapshot)
	assert_null(failed.collision_snapshot)
	assert_null(failed.final_snapshot)
	assert_true(failed.events.is_empty())
	assert_true(failed.entity_contacts.is_empty())
	assert_true(failed.rng_consumers.is_empty())
	# Widen only the test-owned guard to allow retrying the same unconsumed tick.
	run._exploration_guard.world_bounds = Rect2i(-256, -256, 512, 512)
	var retry: TickResult = _tick(run)
	assert_eq(retry.error, "")
	if retry.error.is_empty():
		assert_eq(retry.final_snapshot.tick_index, 1)
		assert_eq(retry.final_snapshot.current_entity_index, 4)
		assert_eq(retry.final_snapshot.rng_draw_count, 2)
		assert_true(retry.events.has("camera_stun_shake"))
		assert_true(retry.events.has("platform_attachment"))
