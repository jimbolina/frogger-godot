extends GutTest
## Frog tint, croak timeline, C particle generator constants and the effect rules against tests/golden/synthetic/effects.json.
##
## The shadow, trail, splash, splash offset, pop ring, score popup and glow
## families run through the presentation rule classes; shadow heights depend
## on a level grid, so the cases check the height rules, not values. The
## poly-piece family belongs to test_effects_pieces.

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

func _matrix(rotation_value: Variant, translation: Vector3i) -> PackedInt32Array:
	var matrix := PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, translation.x, translation.y, translation.z])
	if rotation_value is Array:
		var rotation: Array = rotation_value
		for index: int in 9:
			matrix[index] = _int(rotation[index])
	return matrix

func _offsets(value: Variant) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var rows: Array = value
	for row: Variant in rows:
		result.append(_vector(row))
	return result

func _pairs_xz(points: Array[Vector3i]) -> Array:
	var result: Array = []
	for point: Vector3i in points:
		result.append([PlatformMath.s16(point.x), PlatformMath.s16(point.z)])
	return result

func _ints(value: Variant) -> Array:
	var result: Array = []
	var values: Array = value
	for item: Variant in values:
		result.append(_int(item) if not item is Array else _ints(item))
	return result

func test_frog_shadow_phase_matches_independent_facts() -> void:
	var cases: Array = _facts["frog_shadow_phase"]
	assert_gt(cases.size(), 0)
	for index: int in cases.size():
		var case: Dictionary = cases[index]
		var input: Dictionary = case["input"]
		var expected: Dictionary = case["expected"]
		var mode: int = FrogMode.JUMPING if input["mode"] == "jumping" else FrogMode.STATIONARY
		var flags: int = 0
		var superjump: bool = input["superjump"]
		if superjump:
			flags |= FrogFlags.SUPERJUMP
		if input.get("on_spot", false):
			flags |= FrogFlags.JUMP_ON_SPOT
		var label: String = "shadow phase %d" % index
		var jump_phase: int = FrogShadowGeometry.phase(mode, flags, _int(input["fr_count"]))
		assert_eq(jump_phase, _int(expected["count"]), label + " count")
		assert_eq(FrogShadowGeometry.PHASE_TABLES[jump_phase] + 1, _int(expected["offsets_table"]), label + " table")
		assert_eq(FrogShadowGeometry.phase_offsets(jump_phase), _offsets(expected["offsets"]), label + " offsets")
		var texture: String = expected["texture"]
		assert_eq(FrogShadowGeometry.PHASE_TEXTURES[jump_phase], texture, label + " texture")

func test_frog_shadow_layout_matches_independent_facts() -> void:
	_check_shadow_family("frog_shadow")

func test_shadow_split_matches_independent_facts() -> void:
	_check_shadow_family("shadow_split")

func _check_shadow_family(family: String) -> void:
	var cases: Array = _facts[family]
	assert_gt(cases.size(), 0)
	assert_eq(FrogShadowView.DEPTH_BIAS, -2.0 * FrogShadowGeometry.OT_OFFSET, "four slots nearer")
	for index: int in cases.size():
		var case: Dictionary = cases[index]
		var input: Dictionary = case["input"]
		var expected: Dictionary = case["expected"]
		var label: String = "%s %d %s" % [family, index, input["name"]]
		var translation: Vector3i = _vector(input["translation"])
		var no_rotation: bool = input["no_rotation"]
		var base: Array = input["grid_base"]
		var texture: Dictionary = input["texture_uv"]
		var uv := FrogShadowGeometry.TextureUv.new()
		uv.u = PackedInt32Array([_int(texture["u0"]), _int(texture["u1"]), _int(texture["u2"]), _int(texture["u3"])])
		uv.v = PackedInt32Array([_int(texture["v0"]), _int(texture["v1"]), _int(texture["v2"]), _int(texture["v3"])])
		uv.h = _int(texture["h"])
		var shape: FrogShadowGeometry.Layout = FrogShadowGeometry.layout(_offsets(input["offsets"]), translation, _matrix(input["rotation"], translation), no_rotation, Vector2i(_int(base[0]), _int(base[1])), uv)
		if no_rotation:
			var reordered: bool = expected["reordered"]
			assert_true(expected["quadrant"] == null, label + " quadrant")
			assert_eq(shape.reordered, reordered, label + " reordered")
		else:
			assert_true(expected["reordered"] == null, label + " reordered")
			assert_eq(shape.quadrant, _int(expected["quadrant"]), label + " quadrant")
		assert_eq(_pairs_xz(shape.corners), _ints(expected["corners"]), label + " corners")
		var split: bool = expected["split"]
		assert_eq(shape.split, split, label + " split")
		if split:
			var alignment: String = expected["alignment"]
			assert_eq(shape.alignment, alignment, label + " alignment")
		else:
			assert_true(expected["alignment"] == null, label + " alignment")
		var polys: Array = expected["polys"]
		assert_eq(shape.polys.size(), polys.size(), label + " poly count")
		for poly: int in mini(polys.size(), shape.polys.size()):
			var points: Array = polys[poly]
			for corner: int in 4:
				var point: FrogShadowGeometry.Point = shape.polys[poly][corner]
				var want: Dictionary = points[corner]
				var rule: String = want["height"]
				assert_eq([point.x, point.z, point.height_rule()], [_int(want["x"]), _int(want["z"]), rule], "%s poly %d corner %d" % [label, poly, corner])
		var uvs: Array = []
		for poly: Array in shape.uvs:
			var corners: Array = []
			for texel: Vector2i in poly:
				corners.append([texel.x, texel.y])
			uvs.append(corners)
		assert_eq(uvs, _ints(expected["uv"]), label + " uv")
		if expected.has("split_v"):
			assert_eq(shape.split_v, _int(expected["split_v"]), label + " split v")
		var name: String = input["name"]
		var texture_symbol: String = expected["texture"]
		if name.begins_with("phase"):
			assert_eq(FrogShadowGeometry.PHASE_TEXTURES[name.substr(5).to_int()], texture_symbol, label + " texture")
		elif no_rotation:
			assert_eq(FrogShadowGeometry.NO_ROTATION_TEXTURE, texture_symbol, label + " texture")
		assert_eq([FrogShadowGeometry.GREY, FrogShadowGeometry.GREY, FrogShadowGeometry.GREY], _ints(expected["rgb"]), label + " rgb")
		assert_eq(FrogShadowGeometry.OT_OFFSET, _int(expected["ot_offset"]), label + " ot offset")
		var semi_transparent: bool = expected["semi_transparent"]
		assert_true(semi_transparent, label + " semi-transparent")

func test_hop_trail_matches_independent_facts() -> void:
	var cases: Array = _facts["hop_trail"]
	assert_gt(cases.size(), 0)
	for case: Dictionary in cases:
		var input: Dictionary = case["input"]
		var expected: Dictionary = case["expected"]
		var label: String = input["name"]
		assert_eq(HopTrailState.SECTIONS, _int(expected["sections"]), label + " sections")
		assert_eq(HopTrailState.OFFSETS, _offsets(expected["offsets"]), label + " offsets")
		var hops: Dictionary = {}
		var hop_list: Array = input["hops"]
		for hop: Dictionary in hop_list:
			hops[_int(hop["tick"])] = hop["super"]
		var translations: Array = input["translations"]
		var rows: Array = expected["rows"]
		var trail := HopTrailState.new()
		for tick: int in translations.size():
			if hops.has(tick):
				var superjump: bool = hops[tick]
				trail.start(superjump)
			trail.step(_matrix(input["rotation"], _vector(translations[tick])))
			var row: Dictionary = rows[tick]
			var at: String = "%s tick %d" % [label, tick]
			var rgb: Vector3i = HopTrailState.bytes(trail.rgb)
			var drawn: bool = row["drawn"]
			assert_eq([trail.timer, [rgb.x, rgb.y, rgb.z], trail.display_sections, trail.current_section, trail.drawn()],
				[_int(row["timer"]), _ints(row["rgb"]), _int(row["display_sections"]), _int(row["current_section"]), drawn], at)
			if not trail.drawn():
				continue
			var colours: Array = []
			for colour: int in trail.section_colours():
				var bytes: Vector3i = HopTrailState.bytes(colour)
				colours.append([bytes.x, bytes.y, bytes.z])
			assert_eq(colours, _ints(row["section_rgb"]), at + " section colours")
			var pairs: Array = []
			for pair: Array in trail.pairs():
				var points: Array = []
				for point: Vector3i in pair:
					points.append([point.x, point.y, point.z])
				pairs.append(points)
			assert_eq(pairs, _ints(row["pairs"]), at + " pairs")

func test_splash_timeline_matches_independent_facts() -> void:
	var cases: Array = _facts["splash_timeline"]
	assert_gt(cases.size(), 0)
	for case: Dictionary in cases:
		var input: Dictionary = case["input"]
		var expected: Dictionary = case["expected"]
		var label: String = input["list"]
		var listed: Array = []
		for command: SplashTimeline.Command in SplashTimeline.splash_list():
			var entry: Array = [SplashTimeline.OP_NAMES[command.op]]
			if command.op == SplashTimeline.Op.SETIMAGE:
				entry.append(command.image)
			elif command.op != SplashTimeline.Op.NOP and command.op != SplashTimeline.Op.KILL:
				entry.append(command.value)
			listed.append(entry)
		var animlist: Array = expected["animlist"]
		var wanted: Array = []
		for entry: Array in animlist:
			var wanted_entry: Array = [entry[0]]
			if entry.size() >= 2:
				wanted_entry.append(entry[1] if entry[1] is String else _int(entry[1]))
			wanted.append(wanted_entry)
		assert_eq(listed, wanted, label + " list")
		var timeline := SplashTimeline.new()
		var initial: Array = expected["initial_rgb"]
		var start_rgb: Vector3i = timeline.rgb()
		assert_eq([timeline.scale, [start_rgb.x, start_rgb.y, start_rgb.z]], [_int(expected["initial_scale"]), _ints(initial)], label + " initial")
		var killed_at: int = -1
		var rows: Array = expected["rows"]
		for row: Dictionary in rows:
			timeline.update()
			var tick: int = _int(row["tick"])
			var image: String = "" if row["image"] == null else str(row["image"])
			var executed: Array = row["executed"]
			var killed: bool = row["killed"]
			var rgb: Vector3i = timeline.rgb()
			assert_eq([Array(timeline.executed), timeline.image, timeline.scale, [rgb.x, rgb.y, rgb.z], timeline.speed, timeline.count, timeline.killed],
				[executed, image, _int(row["scale"]), _ints(row["rgb"]), _int(row["speed"]), _int(row["count"]), killed], "%s update %d" % [label, tick])
			if timeline.killed and killed_at < 0:
				killed_at = tick
		assert_eq(killed_at, _int(expected["kill_update"]), label + " kill update")

func test_pop_ring_matches_independent_facts() -> void:
	var cases: Array = _facts["pop_ring"]
	assert_gt(cases.size(), 0)
	for case: Dictionary in cases:
		var input: Dictionary = case["input"]
		var expected: Dictionary = case["expected"]
		var colour: int = _int(input["colour"])
		var label: String = "pop ring player %d" % _int(input["player"])
		var projection: Dictionary = expected["projection"]
		assert_eq([PopRingGeometry.DURATION, PopRingGeometry.SYSTEM_PERSPECTIVE], [_int(expected["duration"]), _int(projection["z"])], label + " constants")
		var ring := PopRingGeometry.new(colour)
		var rows: Array = expected["rows"]
		for row: Dictionary in rows:
			ring.step()
			var life: int = _int(row["life"])
			assert_eq(ring.life, life, label + " life")
			var shape: PopRingGeometry.Frame = ring.frame(_int(row["game_timer"]))
			var outer: Array = []
			for point: Vector2i in shape.outer:
				outer.append([point.x, point.y])
			var inner: Array = []
			for point: Vector2i in shape.inner:
				inner.append([point.x, point.y])
			assert_eq([shape.scale, shape.angle, shape.cosine, shape.sine, outer, inner, [shape.outer_rgb.x, shape.outer_rgb.y, shape.outer_rgb.z], [shape.inner_rgb.x, shape.inner_rgb.y, shape.inner_rgb.z]],
				[_int(row["scale"]), _int(row["angle"]), _int(row["cos"]), _int(row["sin"]), _ints(row["outer"]), _ints(row["inner"]), _ints(row["outer_rgb"]), _ints(row["inner_rgb"])], "%s life %d" % [label, life])
		ring.step()
		assert_false(ring.drawn(), label + " ends at life 0")

func test_score_popup_matches_independent_facts() -> void:
	var cases: Array = _facts["score_popup"]
	assert_gt(cases.size(), 0)
	for case: Dictionary in cases:
		var input: Dictionary = case["input"]
		var expected: Dictionary = case["expected"]
		var start := Vector2i(_int(input["x"]), _int(input["y"]))
		var label: String = "score popup %s" % start
		var popup := ScorePopupState.new(1, start)
		var start_rgb: Array = expected["start_rgb"]
		assert_eq([popup.timer, popup.grey], [_int(expected["lifetime"]), _int(start_rgb[0])], label + " start")
		var killed_at: int = -1
		var rows: Array = expected["rows"]
		for row: Dictionary in rows:
			popup.update()
			var tick: int = _int(row["tick"])
			var at: String = "%s update %d" % [label, tick]
			var killed: bool = row["killed"]
			assert_eq([popup.timer, popup.killed], [_int(row["timer"]), killed], at)
			if popup.killed:
				killed_at = tick if killed_at < 0 else killed_at
				continue
			assert_eq([popup.y_16, [popup.screen().x, popup.screen().y], [popup.grey, popup.grey, popup.grey]], [_int(row["y_16"]), _ints(row["screen"]), _ints(row["rgb"])], at)
		assert_eq(killed_at, _int(expected["kill_update"]), label + " kill update")

func test_splash_offsets_match_independent_facts() -> void:
	var cases: Array = _facts["splash_offsets"]
	assert_gt(cases.size(), 0)
	for case: Dictionary in cases:
		var input: Dictionary = case["input"]
		var expected: Dictionary = case["expected"]
		var theme: int = _int(input["theme"])
		var form_id: int = _int(input["formid"])
		var label: String = "theme %d form %d" % [theme, form_id]
		var defined: bool = expected["source_defined"]
		assert_eq(SplashOffsets.source_defined(theme, form_id), defined, label + " defined")
		if not defined:
			continue
		var sprites: Array = []
		for offset: Vector3i in SplashOffsets.offsets(theme, form_id):
			sprites.append([offset.x, offset.y, offset.z])
		var in_plane: bool = expected["in_xz_plane"]
		assert_eq([sprites, SplashOffsets.IN_XZ_PLANE, SplashOffsets.OT_OFFSET], [_ints(expected["sprites"]), in_plane, _int(expected["ot_offset"])], label)
		assert_eq(SplashView.DEPTH_BIAS, EffectSpriteMaterial.slots_bias(SplashOffsets.OT_OFFSET), label + " depth bias")

func _check_glow(family: String, depth_bias: float) -> void:
	var cases: Array = _facts[family]
	assert_gt(cases.size(), 1)
	var first: Dictionary = cases[0]
	var expected: Dictionary = first["expected"]
	var constants: Dictionary = expected["constants"]
	var texture: String = constants["pc_texture"]
	assert_eq([GlowPulse.STEP, GlowPulse.ANGLE_MASK, GlowPulse.BASE, GlowPulse.MAGNITUDE_SHIFT, EffectResources.GLOW_SYMBOL],
		[_int(constants["pulse_step"]), _int(constants["angle_mask"]), _int(constants["base"]), _int(constants["magnitude_shift"]), texture], family + " constants")
	assert_eq(depth_bias, EffectSpriteMaterial.slots_bias(_int(constants["ot_offset"])), family + " ordering offset")
	var angle: int = 0
	var rows: Array = expected["rows"]
	for row: Dictionary in rows:
		var tick: int = _int(row["tick"])
		angle = GlowPulse.step(angle)
		assert_eq([angle, GlowPulse.angle_after(tick), GlowPulse.magnitude(angle)], [_int(row["angle"]), _int(row["angle"]), _int(row["magnitude"])], "%s tick %d" % [family, tick])
	for index: int in range(1, cases.size()):
		var case: Dictionary = cases[index]
		var input: Dictionary = case["input"]
		var result: Dictionary = case["expected"]
		var size: Vector2i = GlowPulse.half_size(_int(input["w"]), _int(input["h"]), _int(input["otz"]), _int(input["angle"]), _int(input["viewports"]))
		assert_eq([GlowPulse.magnitude(_int(input["angle"])), size.x, size.y], [_int(result["magnitude"]), _int(result["xofs"]), _int(result["yofs"])], "%s case %d" % [family, index])

func test_gold_glow_matches_independent_facts() -> void:
	_check_glow("gold_glow", GoldGlowView.DEPTH_BIAS)
	var cases: Array = _facts["gold_glow"]
	var first: Dictionary = cases[0]
	var expected: Dictionary = first["expected"]
	var constants: Dictionary = expected["constants"]
	assert_eq([GoldGlowView.COLOUR.x, GoldGlowView.COLOUR.y, GoldGlowView.COLOUR.z], _ints(constants["pc_rgb"]), "gold glow PC colour")
	assert_eq(GoldGlowView.OT_OFFSET, _int(constants["ot_offset"]))

func test_pickup_glow_matches_independent_facts() -> void:
	_check_glow("pickup_glow", CaveSpriteView.PICKUP_DEPTH_BIAS)
	assert_eq(CaveSpriteView.GLOW_TEXTURE_ID, EffectResources.GLOW_TEXTURE_ID)
	for age: int in 20:
		assert_eq(CaveSpriteView.glow_magnitude(age), GlowPulse.magnitude(GlowPulse.angle_after(age)), "pickup pulse age %d" % age)
