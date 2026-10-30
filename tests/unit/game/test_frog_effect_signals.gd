extends GutTest
## Hand-derived frozen frog tint, croak timeline, cave light switch and water splash signals.

const BOUNDS: Rect2i = Rect2i(-1000, -2000, 3000, 5000)

func _frog_state(translation: Vector3i) -> FrogState:
	var frog := FrogState.new()
	frog.matrix12[9] = translation.x
	frog.matrix12[10] = translation.y
	frog.matrix12[11] = translation.z
	return frog

func _samples(ids: PackedInt32Array) -> Array[LogicalSoundDefinition]:
	var result: Array[LogicalSoundDefinition] = []
	for id: int in ids:
		var sample := LogicalSoundDefinition.new()
		sample.sound_id = id
		sample.frame_count = 10000
		result.append(sample)
	return result

func _definition(kind: EntityBehavior.Kind, index: int, form_id: int, position: Vector3i) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = index
	definition.form_id = form_id
	definition.behavior.kind = kind
	definition.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, position.x, position.y, position.z])
	return definition

## Frog at the origin; checkpoint 3 is nearest but collected, 0 is beyond sixteen squares, 2 answers.
func _croak_world(with_gold: bool) -> Array:
	var frog := Frog.new()
	frog.random = SourceRandom.create(1)
	frog.entity_collision = EntityCollisionDefinition.new()
	var state := GameplayState.new()
	state.sound = LogicalSoundState.create(_samples([3, 16, 18]))
	state.entity_environment = EntityEnvironmentState.new()
	state.entity_environment.checkpoint_positions.assign([Vector3i(5000, 0, 0), Vector3i(0, 0, 4200), Vector3i(300, 0, 0), Vector3i(200, 0, 0), Vector3i(0, 4500, 0)])
	state.entity_environment.collected = 1 << 3
	state.entity_environment.light_max_squared = 0x600000
	state.entity_environment.light_min_squared = 0x500000
	state.entities = EntityRunSnapshot.new()
	for index: int in 5:
		var definition: EntityDefinition = _definition(EntityBehavior.Kind.CHECKPOINT, 10 + index, index, state.entity_environment.checkpoint_positions[index])
		frog.entity_collision.entities.append(definition)
		var entity := EntitySnapshot.new()
		entity.entity_index = definition.entity_index
		entity.matrix12 = definition.matrix12.duplicate()
		state.entities.entities.append(entity)
	if with_gold:
		var gold: EntityDefinition = _definition(EntityBehavior.Kind.GOLD_FROG, 20, 0, Vector3i(100, 0, 0))
		frog.entity_collision.entities.append(gold)
		var entity := EntitySnapshot.new()
		entity.entity_index = gold.entity_index
		entity.matrix12 = gold.matrix12.duplicate()
		state.entities.entities.append(entity)
	return [frog, state]

func _last(events: Array[TickEvent]) -> String:
	return events[events.size() - 1].to_trace_line() if not events.is_empty() else ""

func _press(mask: int = TickCommand.CROAK) -> TickCommand:
	var command := TickCommand.new()
	command.pressed_mask = mask
	return command

func _level(water_cell: Vector2i) -> LevelDefinition:
	var result := LevelDefinition.new()
	result.grid = GridDefinition.new()
	result.grid.dimensions = Vector2i(3, 3)
	for z: int in 3:
		for x: int in 3:
			var stack := GridStackDefinition.new()
			stack.first_square_index = result.grid.squares.size()
			stack.square_count = 1
			result.grid.stacks.append(stack)
			var square := GridSquareDefinition.new()
			square.flags = GridSquareFlags.USABLE | (GridSquareFlags.WATER if Vector2i(x, z) == water_cell else GridSquareFlags.SAFE)
			square.vertices.assign([Vector3i(x * 256, 0, (z + 1) * 256), Vector3i((x + 1) * 256, 0, (z + 1) * 256), Vector3i(x * 256, 0, z * 256), Vector3i((x + 1) * 256, 0, z * 256)])
			result.grid.squares.append(square)
	return result

func test_edge_fade_scales_by_half_the_unsigned_distance_outside_the_fade_rectangle() -> void:
	assert_eq(FrogTint.edge_fade(Vector3i(0, 0, 0), BOUNDS), 128)
	assert_eq(FrogTint.edge_fade(Vector3i(-1000, 9, 3000), BOUNDS), 128, "The rectangle edges are inside")
	assert_eq(FrogTint.edge_fade(Vector3i(-1100, 0, 0), BOUNDS), 78)
	assert_eq(FrogTint.edge_fade(Vector3i(2101, 0, 3051), BOUNDS), 52)
	assert_eq(FrogTint.edge_fade(Vector3i(0, 0, -2003), BOUNDS), 127, "Odd sums truncate")
	assert_eq(FrogTint.edge_fade(Vector3i(-1300, 0, -2000), BOUNDS), 0, "Fade clamps at zero")

func test_drowning_scale_uses_arithmetic_shifts_without_upper_clamp() -> void:
	var rows: Array = [
		[0, Vector3i(0, 64, 192), Vector3i(0, 128, 32)],
		[1, Vector3i(0, 63, 191), Vector3i(0, 128, 31)],
		[16, Vector3i(0, 63, 191), Vector3i(0, 129, 31)],
		[70, Vector3i(0, 59, 187), Vector3i(0, 132, 27)],
		[-40, Vector3i(1, 66, 194), Vector3i(1, 125, 34)],
		[-2000, Vector3i(62, 189, 317), Vector3i(62, 3, 157)],
		[5000, Vector3i(0, 0, 0), Vector3i(0, 440, 0)],
	]
	for row: Array in rows:
		var delta_y: int = row[0]
		var water: Vector3i = row[1]
		var sludge: Vector3i = row[2]
		assert_eq(FrogTint.drowning_scale(delta_y, 5), water, "Blue water at dy %d" % delta_y)
		assert_eq(FrogTint.drowning_scale(delta_y, FrogTint.THEME_SWAMP), sludge, "Swamp sludge at dy %d" % delta_y)

func test_update_fades_outside_cave_maps_and_drowning_replaces_both_colours() -> void:
	var frog: FrogState = _frog_state(Vector3i(-1100, 116, 0))
	FrogTint.update(frog, false, BOUNDS, 5)
	assert_eq([frog.colour_scale, frog.custom_ambient, frog.tint_flags], [Vector3i(78, 78, 78), Vector3i(128, 128, 128), FrogTint.SCALED_COLOURS])
	frog.mode = FrogMode.DYING
	frog.death_equate = FrogAnimationCatalog.DROWN
	frog.old_y = 100
	FrogTint.update(frog, false, BOUNDS, 5)
	assert_eq([frog.colour_scale, frog.custom_ambient, frog.tint_flags], [Vector3i(0, 63, 191), Vector3i(32, 64, 64), FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS])
	frog.matrix12[10] = -1900
	FrogTint.update(frog, false, BOUNDS, 5)
	assert_eq(frog.colour_scale, Vector3i(62, 189, 61), "The blue byte store truncates 317")
	frog.matrix12[10] = 5100
	FrogTint.update(frog, true, BOUNDS, FrogTint.THEME_SWAMP)
	assert_eq(frog.colour_scale, Vector3i(0, 184, 0), "The green byte store truncates 440")
	var cave: FrogState = _frog_state(Vector3i(-5000, 0, 0))
	cave.colour_scale = Vector3i(1, 2, 3)
	FrogTint.update(cave, true, BOUNDS, 1)
	assert_eq([cave.colour_scale, cave.tint_flags], [Vector3i(1, 2, 3), 0], "Cave maps keep the colour scale")
	cave.mode = FrogMode.DYING
	cave.death_equate = FrogAnimationCatalog.FLOP
	FrogTint.update(cave, true, BOUNDS, 1)
	assert_eq(cave.tint_flags, 0, "Only drowning tints")

func test_reset_packs_the_signed_header_ambient_with_its_low_byte_in_red() -> void:
	var frog := FrogState.new()
	frog.tint_flags = FrogTint.SCALED_COLOURS
	FrogTint.reset(frog, Vector3i(10, -20, 30))
	assert_eq([frog.custom_ambient, frog.tint_flags], [Vector3i(158, 108, 138), FrogTint.CUSTOM_AMBIENT])
	FrogTint.reset(frog, Vector3i(0, 0, -200))
	assert_eq(frog.custom_ambient, Vector3i(184, 127, 128), "Negative sliders borrow across bytes")
	FrogTint.reset(frog, Vector3i.ZERO)
	assert_eq([frog.custom_ambient, frog.tint_flags], [Vector3i(184, 127, 128), 0], "A zero header only clears the flags")

func test_volcano_char_sets_both_colours_until_the_base_colour_update() -> void:
	var frog := Frog.new()
	frog.theme = 10
	var state := GameplayState.new()
	var events: Array[TickEvent] = []
	frog.kill(state, FrogAnimationCatalog.FLOP, false, events)
	assert_eq(state.requests.death_scale_colour, Vector3i(24, 0, 0))
	assert_eq([state.frog.custom_ambient, state.frog.colour_scale, state.frog.tint_flags], [Vector3i(24, 0, 0), Vector3i(24, 0, 0), FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS])
	FrogTint.update(state.frog, false, BOUNDS, 10)
	assert_eq([state.frog.custom_ambient, state.frog.colour_scale], [Vector3i(24, 0, 0), Vector3i(128, 128, 128)], "The edge fade replaces the scale")
	state.frog.mode = FrogMode.DYING
	FrogTint.update(state.frog, false, BOUNDS, 10)
	assert_eq(state.frog.custom_ambient, Vector3i(24, 0, 0), "A FLOP death keeps the char ambient")
	var drowned := GameplayState.new()
	frog.kill(drowned, FrogAnimationCatalog.DROWN, true, events)
	drowned.frog.mode = FrogMode.DYING
	FrogTint.update(drowned.frog, false, BOUNDS, 10)
	assert_eq(drowned.frog.custom_ambient, Vector3i(32, 64, 64), "A DROWN death equate takes the water tint")
	var plain := GameplayState.new()
	Frog.new().kill(plain, FrogAnimationCatalog.DROWN, true, events)
	assert_eq(plain.frog.tint_flags, 0, "Only Volcano chars the frog")

func test_croak_inflates_holds_deflates_and_answers_the_nearest_checkpoint() -> void:
	var world: Array = _croak_world(false)
	var frog: Frog = world[0]
	var state: GameplayState = world[1]
	var environment: EntityEnvironmentState = state.entity_environment
	var events: Array[TickEvent] = []
	assert_eq(FrogCroak.update(frog, state, _press(), events), "")
	assert_eq([state.frog.croak_mode, state.frog.croak_timer, state.frog.croak_scale], [FrogCroak.Mode.INFLATE, 6, 0x200])
	assert_eq([state.frog.croak_radius_max, state.frog.croak_radius_min, state.frog.croak_rate], [0x600000, 0x500000, 0x100000])
	assert_false(environment.light_switch)
	assert_eq(TickEvent.trace_lines(events), ["croak"])
	assert_eq(state.sound.voices[0].sample.sound_id, 3)
	assert_eq(state.requests.sound_requests, 1)
	var scales := PackedInt32Array([938, 1365, 1792, 2218, 2645, 3072, 3072, 3072, 3072, 3072, 2645, 2218, 1792, 1365, 938, 512])
	var modes := PackedInt32Array([1, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 0])
	var timers := PackedInt32Array([5, 4, 3, 2, 1, 4, 3, 2, 1, 6, 5, 4, 3, 2, 1, 0])
	var swell := PackedInt32Array([1, 2, 3, 4, 5, 6, 6, 6, 6, 6, 5, 4, 3, 2, 1, 0])
	for tick: int in 16:
		events.clear()
		assert_eq(FrogCroak.update(frog, state, _press(0), events), "")
		assert_eq([state.frog.croak_mode, state.frog.croak_timer, state.frog.croak_scale], [modes[tick], timers[tick], scales[tick]], "Tick %d" % (tick + 1))
		assert_eq([environment.light_max_squared, environment.light_min_squared], [0x600000 + swell[tick] * 0x100000, 0x500000 + swell[tick] * 0x100000], "Tick %d radii" % (tick + 1))
		assert_eq(environment.light_switch, tick == 15)
		if tick < 15:
			assert_true(events.is_empty())
	assert_eq(TickEvent.trace_lines(events), ["entity:12:moving:16:-1:-1"])
	assert_eq(environment.croak_modes, PackedInt32Array([0, 0, 1, 0, 0]))
	var moving: LogicalMovingSound = state.sound.moving_for(12)
	assert_not_null(moving)
	if moving != null:
		assert_eq([moving.sound_id, moving.near_radius, moving.far_radius, moving.position], [16, 1792, 7168, Vector3i(300, 0, 0)])

func test_croak_restores_saved_radii_and_wraps_the_swell_unsigned() -> void:
	var world: Array = _croak_world(false)
	var frog: Frog = world[0]
	var state: GameplayState = world[1]
	var environment: EntityEnvironmentState = state.entity_environment
	environment.light_max_squared = 0xfffffffa
	environment.light_min_squared = 0xfffffff0
	var events: Array[TickEvent] = []
	FrogCroak.update(frog, state, _press(), events)
	assert_eq(state.frog.croak_rate, 0x2aaaaaa9)
	FrogCroak.update(frog, state, _press(0), events)
	assert_eq([environment.light_max_squared, environment.light_min_squared], [0x2aaaaaa3, 0x2aaaaa99])
	FrogCroak.update(frog, state, _press(0), events)
	environment.light_max_squared = 7
	for tick: int in 14:
		FrogCroak.update(frog, state, _press(0), events)
	assert_eq([environment.light_max_squared, environment.light_min_squared], [0xfffffffa, 0xfffffff0])

func test_croak_answer_prefers_a_closer_uncollected_gold_frog() -> void:
	var world: Array = _croak_world(true)
	var frog: Frog = world[0]
	var state: GameplayState = world[1]
	assert_eq(FrogCroak.nearest_checkpoint(frog, state).entity_index, 20)
	var events: Array[TickEvent] = []
	state.frog.croak_mode = FrogCroak.Mode.DEFLATE
	state.frog.croak_timer = 1
	assert_eq(FrogCroak.update(frog, state, _press(0), events), "")
	assert_eq(TickEvent.trace_lines(events), ["entity:20:moving:18:-1:-1"])
	assert_eq(state.entity_environment.croak_modes, PackedInt32Array([0, 0, 0, 0, 0]))
	state.flow.gold_collected = true
	assert_eq(FrogCroak.nearest_checkpoint(frog, state).entity_index, 12)
	state.entity_environment.collected = 31
	assert_null(FrogCroak.nearest_checkpoint(frog, state))
	state.entities.entities[2].live = false
	state.entity_environment.collected = 1 << 3
	state.flow.gold_collected = true
	events.clear()
	state.frog.croak_mode = FrogCroak.Mode.DEFLATE
	state.frog.croak_timer = 1
	FrogCroak.update(frog, state, _press(0), events)
	assert_true(events.is_empty(), "A checkpoint without a live entity croaks silently")
	assert_eq(state.entity_environment.croak_modes, PackedInt32Array([0, 0, 1, 0, 0]))

func test_croak_skips_demos_inactive_control_and_checkpoint_hits() -> void:
	var world: Array = _croak_world(false)
	var frog: Frog = world[0]
	var state: GameplayState = world[1]
	var events: Array[TickEvent] = []
	var demo: TickCommand = _press()
	demo.recorded_input_byte = 0
	FrogCroak.update(frog, state, demo, events)
	var exhausted: TickCommand = _press()
	exhausted.recorded_input_exhausted = true
	FrogCroak.update(frog, state, exhausted, events)
	assert_eq(state.frog.croak_mode, FrogCroak.Mode.NONE)
	state.frog.mode = FrogMode.HIT_CHECKPOINT
	FrogCroak.update(frog, state, _press(), events)
	state.frog.mode = FrogMode.STATIONARY
	state.frog.flags &= ~FrogFlags.CONTROL_ACTIVE
	FrogCroak.update(frog, state, _press(), events)
	FrogCroak.update(frog, state, _press(TickCommand.TONGUE), events)
	assert_eq(state.frog.croak_mode, FrogCroak.Mode.NONE)
	assert_true(events.is_empty())
	assert_true(state.entity_environment.light_switch)
	state.frog.croak_mode = FrogCroak.Mode.INFLATE
	state.frog.croak_timer = 6
	FrogCroak.update(frog, state, demo, events)
	assert_eq([state.frog.croak_timer, state.frog.croak_scale], [6, 0x200], "Demos freeze a running croak")
	FrogCroak.update(frog, state, _press(0), events)
	assert_eq(state.frog.croak_timer, 5, "A running croak continues without control")

func test_cave_light_decay_waits_for_the_light_switch() -> void:
	var definition := EntityDefinition.new()
	definition.cave = EntityCaveDefinition.new()
	definition.cave.light_max_squared = 0x200000
	definition.cave.light_min_squared = 0x10000
	definition.cave.light_die = 0x1000
	var environment := EntityEnvironmentState.new()
	environment.light_max_squared = 0x300000
	environment.light_min_squared = 0x200000
	environment.light_switch = false
	var result := EntityCustomResult.new()
	result.environment = environment
	assert_eq(EntityCaveLight.update(definition, result), "")
	assert_eq([environment.light_max_squared, environment.light_min_squared], [0x300000, 0x200000])
	var entity := EntitySnapshot.new()
	EntityCaveLight.initialize(definition, entity, environment)
	assert_true(environment.light_switch)
	assert_eq(EntityCaveLight.update(definition, result), "")
	assert_eq(environment.light_max_squared, 0x1FF000)

func test_water_reactions_and_death_height_request_splashes_at_the_frog_translation() -> void:
	var frog := Frog.new()
	var state := GameplayState.new()
	state.frog.matrix12[9] = 128
	state.frog.matrix12[10] = 40
	state.frog.matrix12[11] = 384
	var events: Array[TickEvent] = []
	frog.react(state, GridSquareFlags.USABLE | GridSquareFlags.WATER, events)
	assert_eq(_last(events), "splash:128:40:384")
	var fall := GameplayState.new()
	fall.frog.matrix12[9] = -7
	events.clear()
	frog.react_fall(fall, 2000, GridSquareFlags.WATER, events)
	assert_eq(_last(events), "splash:-7:0:0")
	events.clear()
	frog.react_fall(GameplayState.new(), 2000, GridSquareFlags.DEADLY, events)
	frog.react(GameplayState.new(), GridSquareFlags.USABLE | GridSquareFlags.DEADLY, events)
	assert_false(TickEvent.trace_lines(events).any(func(line: String) -> bool: return line.begins_with("splash")), "Deadly ground does not splash")
	frog.collision_bounds = Rect2i(-100, -100, 200, 200)
	frog.death_height = 30
	var sink := GameplayState.new()
	sink.frog.world_position = Vector3i(5, 90, -6)
	events.clear()
	frog.collide(sink, events)
	assert_eq(_last(events), "splash:5:30:-6", "The splash sits at the clamped death height")

func test_water_landing_splashes_then_the_sinking_frog_takes_the_blue_tint() -> void:
	var level: LevelDefinition = _level(Vector2i(0, 1))
	level.frog_ambient = Vector3i(10, -20, 30)
	var run: GameplayRun = GameplayRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq([run.snapshot().frog.custom_ambient, run.snapshot().frog.tint_flags], [Vector3i(158, 108, 138), FrogTint.CUSTOM_AMBIENT])
	var lines: Array[String] = []
	var result: TickResult = null
	for tick: int in 6:
		var command := TickCommand.new()
		command.tick_index = tick
		command.pressed_mask = TickCommand.NORTH if tick == 0 else 0
		result = run.step(command)
		assert_eq(result.error, "")
		if not result.error.is_empty():
			return
		lines.append_array(TickEvent.trace_lines(result.events))
	assert_eq(lines.count("splash:128:-40:384"), 1, "The hop lands its last arc height in the water")
	assert_true(TickEvent.trace_lines(result.events).has("splash:128:-40:384"), "The landing tick splashes")
	var landed: FrogState = result.final_snapshot.frog
	assert_eq([landed.colour_scale, landed.custom_ambient, landed.tint_flags], [Vector3i(128, 128, 128), Vector3i(158, 108, 138), FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS])
	for tick: int in range(6, 10):
		var command := TickCommand.new()
		command.tick_index = tick
		result = run.step(command)
		assert_eq(result.error, "")
		if not result.error.is_empty():
			return
	var frog: FrogState = result.final_snapshot.frog
	assert_eq([frog.mode, frog.old_y, frog.matrix12[10]], [FrogMode.DYING, -40, -36])
	assert_eq([frog.colour_scale, frog.custom_ambient, frog.tint_flags], [Vector3i(0, 63, 191), Vector3i(32, 64, 64), FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS])

func test_integrated_croak_accepts_the_croak_bit_and_reset_restores_defaults() -> void:
	var run: GameplayRun = GameplayRun.create(_level(Vector2i(-1, -1)))
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var command := TickCommand.new()
	command.pressed_mask = TickCommand.CROAK | TickCommand.NORTH
	command.held_mask = TickCommand.CROAK
	var result: TickResult = run.step(command)
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	var lines: Array[String] = TickEvent.trace_lines(result.events)
	assert_eq(lines[lines.size() - 1], "croak", "The croak follows the frog's control")
	assert_true(lines.has("hop"), "The croak bit leaves direction selection alone")
	assert_eq(result.final_snapshot.frog.croak_mode, FrogCroak.Mode.INFLATE)
	var invalid := TickCommand.new()
	invalid.tick_index = 1
	invalid.pressed_mask = 512
	assert_ne(run.step(invalid).error, "")
	var state: GameplayState = run.snapshot()
	state.frog.croak_radius_max = 77
	state.frog.croak_radius_min = 66
	state.frog.croak_rate = 11
	state.frog.colour_scale = Vector3i(1, 2, 3)
	state.frog.tint_flags = FrogTint.SCALED_COLOURS | FrogTint.CUSTOM_AMBIENT
	var events: Array[TickEvent] = []
	assert_eq(run._reset_in_level(state, false, events), "")
	assert_eq([state.frog.croak_mode, state.frog.croak_timer, state.frog.croak_scale], [FrogCroak.Mode.NONE, 0, 0x200])
	assert_eq([state.frog.croak_radius_max, state.frog.croak_radius_min, state.frog.croak_rate], [77, 66, 11], "ResetFrog keeps the saved radii")
	assert_eq([state.frog.colour_scale, state.frog.tint_flags], [Vector3i(128, 128, 128), 0])
