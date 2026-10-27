extends GutTest
## Independent frozen Cave light, fade, pickup and sprite facts at source widths.

const LIGHT_REWARDS: Dictionary[String, int] = {"light_5": 12, "light_8": 13, "super_light": 14}

func _facts() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/cave.json"))

func _environment(maximum: int, minimum: int) -> EntityEnvironmentState:
	var environment := EntityEnvironmentState.new()
	for index: int in 5:
		environment.checkpoint_positions.append(Vector3i.ZERO)
	environment.light_max_squared = maximum
	environment.light_min_squared = minimum
	return environment

func _result(environment: EntityEnvironmentState) -> EntityCustomResult:
	var result := EntityCustomResult.new()
	result.entity = EntitySnapshot.new()
	result.environment = environment
	result.random = SourceRandom.create(1)
	return result

func _definition(name: String) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 0
	definition.behavior = EntityBehaviorCatalog.resolve(name)
	return definition

func _int(row: Dictionary, key: String) -> int:
	var value: int = row[key]
	return value

func test_light_creation_precalculation_and_seeding_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().light_create:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var definition: EntityDefinition = _definition("CAV_FROGGER_LIGHT")
		var payload := PackedByteArray()
		payload.resize(48)
		payload.encode_u32(32, _int(initial, "min_radius"))
		payload.encode_u32(36, _int(initial, "max_radius"))
		payload.encode_u32(40, _int(initial, "die_speed"))
		var issue: String = EntitySetup._cave_payload(definition, payload)
		var debug_valid: bool = expected.debug_valid
		if not debug_valid or _int(initial, "max_radius") > 255:
			assert_ne(issue, "", "port admission rejects %s" % str(initial))
			continue
		assert_eq(issue, "", str(initial))
		if definition.cave == null:
			continue
		assert_eq(definition.cave.light_min_squared & 0xffffffff, _int(expected, "min_r2"), str(initial))
		assert_eq(definition.cave.light_max_squared & 0xffffffff, _int(expected, "max_r2"), str(initial))
		assert_eq(definition.cave.light_die & 0xffffffff, _int(expected, "die"), str(initial))
		var environment: EntityEnvironmentState = _environment(0, 0)
		EntityCaveLight.initialize(definition, EntitySnapshot.new(), environment)
		assert_eq(environment.light_max_squared, _int(expected, "map_max"), str(initial))
		assert_eq(environment.light_min_squared, _int(expected, "map_min"), str(initial))

func test_light_crop_and_decay_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().light_decay:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var definition: EntityDefinition = _definition("CAV_FROGGER_LIGHT")
		definition.cave = EntityCaveDefinition.new()
		definition.cave.light_max_squared = _int(initial, "fl_max")
		definition.cave.light_min_squared = _int(initial, "fl_min")
		definition.cave.light_die = _int(initial, "die")
		var result: EntityCustomResult = _result(_environment(_int(initial, "map_max"), _int(initial, "map_min")))
		assert_eq(EntityCaveLight.update(definition, result), "", str(initial))
		assert_eq(result.environment.light_max_squared, _int(expected, "map_max"), str(initial))
		assert_eq(result.environment.light_min_squared, _int(expected, "map_min"), str(initial))

func test_light_pickups_and_firefly_callback_match_independent_facts() -> void:
	var rewards: Array[RewardDefinition] = GameplayRewards.component_definitions()
	for fixture: Dictionary in _facts().light_add:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var state := GameplayState.new()
		state.entity_environment = _environment(_int(initial, "map_max"), _int(initial, "map_min"))
		var frog := Frog.new()
		var events: Array[TickEvent] = []
		var source: String = initial.source
		for _repeat: int in _int(initial, "repeats"):
			if source == "firefly":
				assert_eq(FormCallback.apply(FormCallback.Kind.CAV_FIREFLY_SCORE, frog, state, 0, events), "", str(initial))
			else:
				assert_eq(GameplayRewards.apply(rewards[LIGHT_REWARDS[source]], state, events), "", str(initial))
		assert_eq(state.entity_environment.light_max_squared, _int(expected, "map_max"), str(initial))
		assert_eq(state.entity_environment.light_min_squared, _int(expected, "map_min"), str(initial))
		assert_eq(state.flow.score, _int(expected, "score_delta"), str(initial))

func test_entity_fade_colour_and_scale_policy_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().entity_fade:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var colour: int = EntityCaveFade.colour(Vector3i(_int(initial, "entity_x"), 0, _int(initial, "entity_z")),
			Vector3i(_int(initial, "frog_x"), 0, _int(initial, "frog_z")), _int(initial, "map_min"), _int(initial, "map_max"))
		assert_eq(colour, _int(expected, "colour"), str(initial))
		var definition := EntityDefinition.new()
		var no_model: bool = initial.no_model
		var no_display: bool = initial.no_display
		var dont_fade: int = initial.dont_fade
		definition.form_flags = (1 if no_model else 0) | (256 if dont_fade == 1 else 0)
		var entity := EntitySnapshot.new()
		entity.entity_flags = EntityDefinition.NO_DISPLAY if no_display else 0
		entity.live_flags = EntityLiveFlags.NO_COLOUR_FADE if dont_fade == 2 else 0
		EntityCaveFade.apply(entity, definition, _int(expected, "colour"))
		var scaled: bool = expected.scaled
		var scale: Array = expected.scale
		var wanted := Vector3i.ZERO
		for axis: int in 3:
			var channel: int = scale[axis]
			wanted[axis] = channel
		assert_eq(entity.colour_scaled, scaled, str(initial))
		assert_eq(entity.colour_scale, wanted, str(initial))
		if _int(expected, "sprite") >= 0:
			assert_eq(entity.colour_scale, Vector3i.ONE * _int(expected, "sprite"), str(initial))

func test_fat_fire_fly_bob_and_random_draw_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().fat_fire_fly_bob:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var definition: EntityDefinition = _definition("CAV_FAT_FIRE_FLY")
		definition.unique_id = _int(initial, "uid")
		definition.matrix12[10] = _int(initial, "base_y")
		var result: EntityCustomResult = _result(_environment(0, 0))
		EntityFatFireFly.initialize(definition, result.entity)
		var stopped: bool = initial.stopped
		if stopped:
			result.entity.entity_flags |= EntityDefinition.NO_MOVEMENT
		var frog := GameplayState.new()
		frog.frog.matrix12[9] = 30000
		assert_eq(EntityFatFireFly.update(definition, result, frog, _int(initial, "frame")), "", str(initial))
		assert_eq(result.entity.matrix12[10], _int(expected, "y"), str(initial))
		assert_eq(result.random.draw_count, _int(expected, "draws"), str(initial))

func test_firefly_sprite_frames_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().firefly_frames:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		assert_eq(CaveSpriteView.frame_index(_int(initial, "age")), _int(expected, "image"), str(initial))
