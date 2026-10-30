extends GutTest
## Frog tint, croak timeline and C particle generator constants against tests/golden/synthetic/effects.json.
##
## The shadow, trail, poly-piece, splash, pop ring, score popup and glow
## families describe presentation the port does not evaluate yet, so this
## script has no tests for them.

var _facts: Dictionary = {}

func before_all() -> void:
	_facts = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/effects.json"))

func _int(value: Variant) -> int:
	var result: int = value
	return result

func _vector(value: Variant) -> Vector3i:
	var values: Array = value
	var x: int = values[0]
	var y: int = values[1]
	var z: int = values[2]
	return Vector3i(x, y, z)

func _bounds(top_left_value: Variant, bottom_right_value: Variant) -> Rect2i:
	var top_left: Array = top_left_value
	var bottom_right: Array = bottom_right_value
	var left: int = top_left[0]
	var top: int = top_left[1]
	var right: int = bottom_right[0]
	var bottom: int = bottom_right[1]
	return Rect2i(left, bottom, right - left, top - bottom)

func _samples(ids: PackedInt32Array) -> Array[LogicalSoundDefinition]:
	var result: Array[LogicalSoundDefinition] = []
	for id: int in ids:
		var sample := LogicalSoundDefinition.new()
		sample.sound_id = id
		sample.frame_count = 10000
		result.append(sample)
	return result

func _press(mask: int) -> TickCommand:
	var command := TickCommand.new()
	command.pressed_mask = mask
	return command

func test_drowning_tint_matches_independent_facts() -> void:
	var cases: Array = _facts["frog_tint"]["drown"]
	assert_gt(cases.size(), 0)
	for case: Dictionary in cases:
		var input: Dictionary = case["input"]
		var expected: Dictionary = case["expected"]
		var theme: int = input["theme"]
		var dy: int = input["dy"]
		var label: String = "theme %d dy %d" % [theme, dy]
		assert_eq(FrogTint.drowning_scale(dy, theme), _vector(expected["unmasked"]), label + " unmasked")
		var frog := FrogState.new()
		frog.mode = FrogMode.DYING
		frog.death_equate = FrogAnimationCatalog.DROWN
		frog.old_y = 0
		frog.matrix12[10] = dy
		FrogTint.update(frog, true, Rect2i(), theme)
		assert_eq(frog.colour_scale, _vector(expected["colour_scale"]), label + " colour scale")
		assert_eq(frog.custom_ambient, _vector(expected["custom_ambient"]), label + " custom ambient")
		assert_eq(frog.tint_flags, FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS, label + " flags")

func test_edge_fade_matches_independent_facts() -> void:
	var cases: Array = _facts["frog_tint"]["edge_fade"]
	assert_gt(cases.size(), 0)
	for index: int in cases.size():
		var case: Dictionary = cases[index]
		var input: Dictionary = case["input"]
		var expected: Dictionary = case["expected"]
		var position: Array = input["position"]
		var x: int = position[0]
		var z: int = position[1]
		var bounds: Rect2i = _bounds(input["top_left"], input["bottom_right"])
		var frog := FrogState.new()
		frog.matrix12[9] = x
		frog.matrix12[11] = z
		frog.colour_scale = Vector3i(1, 2, 3)
		var applied: bool = expected["applied"]
		var cave_light: bool = input["cave_light"]
		FrogTint.update(frog, cave_light, bounds, 1)
		if applied:
			var grey: int = expected["grey"]
			assert_eq(FrogTint.edge_fade(Vector3i(x, 0, z), bounds), grey, "edge fade %d grey" % index)
			assert_eq(frog.colour_scale, _vector(expected["colour_scale"]), "edge fade %d colour scale" % index)
			assert_eq(frog.tint_flags, FrogTint.SCALED_COLOURS, "edge fade %d flags" % index)
		else:
			assert_eq([frog.colour_scale, frog.tint_flags], [Vector3i(1, 2, 3), 0], "edge fade %d keeps the cave colour" % index)

func test_volcano_char_matches_independent_facts() -> void:
	var case: Dictionary = _facts["frog_tint"]["volcano_char"]
	var expected: Dictionary = case["expected"]
	var deaths: Array = expected["deaths"]
	assert_eq(deaths.size(), 2)
	for death: String in deaths:
		var animation: int = FrogAnimationCatalog.DROWN if death == "DROWN" else FrogAnimationCatalog.FLOP
		assert_true(death in ["DROWN", "FLOP"], death)
		var frog := Frog.new()
		frog.theme = _int(case["input"]["theme"])
		var state := GameplayState.new()
		var events: Array[TickEvent] = []
		frog.kill(state, animation, false, events)
		assert_true(state.requests.death_fire_requested, death + " requests the fire particles")
		assert_eq(state.requests.death_scale_colour, _vector(expected["colour_scale"]), death + " scale colour")
		assert_eq(state.frog.colour_scale, _vector(expected["colour_scale"]), death + " colour scale")
		assert_eq(state.frog.custom_ambient, _vector(expected["custom_ambient"]), death + " custom ambient")
		var other := GameplayState.new()
		Frog.new().kill(other, animation, false, events)
		assert_false(other.requests.death_fire_requested, death + " chars only on Volcano")

## Low-poly cases check only the saved radii and rate: the port's croak
## models the high-poly single-player frog.
func test_croak_timeline_matches_independent_facts() -> void:
	var cases: Array = _facts["croak_timeline"]
	assert_gt(cases.size(), 0)
	for index: int in cases.size():
		var case: Dictionary = cases[index]
		var input: Dictionary = case["input"]
		var expected: Dictionary = case["expected"]
		var frog := Frog.new()
		frog.random = SourceRandom.create(1)
		frog.entity_collision = EntityCollisionDefinition.new()
		var state := GameplayState.new()
		state.sound = LogicalSoundState.create(_samples(PackedInt32Array([FrogCroak.SOUND_CROAK])))
		state.entity_environment = EntityEnvironmentState.new()
		state.entity_environment.checkpoint_positions.resize(5)
		state.entity_environment.light_max_squared = _int(input["light_max_r2"])
		state.entity_environment.light_min_squared = _int(input["light_min_r2"])
		var events: Array[TickEvent] = []
		assert_eq(FrogCroak.update(frog, state, _press(TickCommand.CROAK), events), "", "croak %d press" % index)
		var saved: Array = expected["saved"]
		assert_eq([state.frog.croak_radius_max, state.frog.croak_radius_min], [_int(saved[0]), _int(saved[1])], "croak %d saved radii" % index)
		assert_eq(state.frog.croak_rate, _int(expected["rate"]), "croak %d rate" % index)
		var high_poly: bool = input["high_poly"]
		if not high_poly:
			continue
		var rows: Array = expected["rows"]
		var restored: int = _int(expected["restored_tick"])
		for row: Dictionary in rows:
			var tick: int = _int(row["tick"])
			if tick > 0:
				assert_eq(FrogCroak.update(frog, state, _press(0), events), "", "croak %d tick %d" % [index, tick])
			var mode: String = row["mode"]
			var label: String = "croak %d tick %d" % [index, tick]
			assert_eq(state.frog.croak_mode, FrogCroak.Mode.keys().find(mode), label + " mode")
			assert_eq(state.frog.croak_timer, _int(row["timer"]), label + " timer")
			assert_eq(state.entity_environment.light_max_squared, _int(row["max_r2"]), label + " max radius")
			assert_eq(state.entity_environment.light_min_squared, _int(row["min_r2"]), label + " min radius")
			assert_eq(state.frog.croak_scale, _int(row["scale"]), label + " scale")
			assert_eq(state.entity_environment.light_switch, tick >= restored, label + " light switch")

func test_generator_parameters_match_the_c_constant_fallback() -> void:
	var cases: Array = _facts["generator_parameters"]
	var fallback: EffectResources = EffectResources.resolve(null, null, null, null, null)
	assert_false(fallback.generators.from_executable)
	assert_eq(fallback.generators.records.size(), cases.size(), "every C initialiser")
	for case: Dictionary in cases:
		var generator_name: String = case["input"]["name"]
		var expected: Dictionary = case["expected"]
		var record: ParticleGeneratorRecord = fallback.generators.find(generator_name)
		assert_not_null(record, generator_name)
		if record == null:
			continue
		for field: String in ["type", "flags", "max_particles", "generator_life", "particle_min_life", "particle_max_life", "gravity_16", "user_data_1"]:
			assert_eq(_int(record.get(field)), _int(expected[field]), "%s %s" % [generator_name, field])
		var source: Variant = expected["texture_source"]
		var symbols := PackedStringArray()
		var kind: ParticleGeneratorRecord.TextureKind = ParticleGeneratorRecord.TextureKind.NONE
		if source is String and source == "user_data_2":
			kind = ParticleGeneratorRecord.TextureKind.TEXTURE
			var texture: String = expected["texture"]
			symbols.append(texture)
		elif source is String and source == "user_data_2_list":
			kind = ParticleGeneratorRecord.TextureKind.TEXTURE_LIST
			var listed: Array = expected["textures"]
			for symbol: String in listed:
				symbols.append(symbol)
		assert_eq(record.texture_kind, kind, generator_name + " texture source")
		assert_eq(record.texture_symbols, symbols, generator_name + " textures")
