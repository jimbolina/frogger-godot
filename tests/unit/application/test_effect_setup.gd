extends GutTest
## Entity hilites resolved into particle placements from synthetic models.

func _hilite(type: int, attach: int, index: int) -> MofPart.Hilite:
	var hilite := MofPart.Hilite.new()
	hilite.type = type
	hilite.attach = attach
	hilite.index = index
	return hilite

func _part(part_index: int, hilites: Array[MofPart.Hilite]) -> MofPart:
	var part := MofPart.new()
	part.index = part_index
	part.hilites = hilites
	part.hilite_count = hilites.size()
	return part

func _model(statics: Array[Array]) -> MofFile:
	var model := MofFile.new()
	model.kind = MofFile.Kind.STATIC
	for parts: Array in statics:
		var static_model := MofStatic.new()
		for part: MofPart in parts:
			static_model.parts.append(part)
		model.static_models.append(static_model)
	return model

func _texts(hilites: Array[ParticleHilite]) -> PackedStringArray:
	var result := PackedStringArray()
	for hilite: ParticleHilite in hilites:
		result.append("%s:%d:%d" % [ParticleHilite.Kind.keys()[hilite.kind], hilite.part, hilite.vertex])
	return result

func test_static_model_zero_hilites_map_through_the_generator_table() -> void:
	var first: MofPart = _part(0, [_hilite(0, MofPart.ATTACH_VERTEX, 9), _hilite(3, MofPart.ATTACH_VERTEX, 1), _hilite(4, MofPart.ATTACH_VERTEX, 2)])
	var second: MofPart = _part(1, [_hilite(5, MofPart.ATTACH_VERTEX, 3), _hilite(6, MofPart.ATTACH_VERTEX, 4)])
	var later: MofPart = _part(0, [_hilite(6, MofPart.ATTACH_VERTEX, 5)])
	var model: MofFile = _model([[first, second], [later]])
	var diagnostics := PackedStringArray()
	var hilites: Array[ParticleHilite] = EffectSetup.hilites_of(model, ExeParticleGenerators.C_SPECIAL_GENERATORS, "model", diagnostics)
	assert_eq(_texts(hilites), PackedStringArray(["EXHAUST:0:1", "EXHAUST:0:2", "DUST:1:3", "FIRE:1:4"]), "Collision hilites and later static models start nothing")
	assert_eq(diagnostics, PackedStringArray())
	var repointed: PackedStringArray = ExeParticleGenerators.C_SPECIAL_GENERATORS.duplicate()
	repointed[4] = "PGIN_hilite_fire"
	assert_eq(_texts(EffectSetup.hilites_of(model, repointed, "model", diagnostics)), PackedStringArray(["EXHAUST:0:1", "FIRE:0:2", "DUST:1:3", "FIRE:1:4"]), "The executable's table selects the generator")

func test_unsupported_types_and_polygon_attachments_are_omitted_with_diagnostics() -> void:
	var part: MofPart = _part(0, [_hilite(1, MofPart.ATTACH_VERTEX, 0), _hilite(7, MofPart.ATTACH_VERTEX, 0), _hilite(12, MofPart.ATTACH_VERTEX, 0), _hilite(6, MofPart.ATTACH_POLYGON, 2), _hilite(6, MofPart.ATTACH_VERTEX, 3)])
	var diagnostics := PackedStringArray()
	var hilites: Array[ParticleHilite] = EffectSetup.hilites_of(_model([[part]]), ExeParticleGenerators.C_SPECIAL_GENERATORS, "model 7", diagnostics)
	assert_eq(_texts(hilites), PackedStringArray(["FIRE:0:3"]))
	assert_eq(diagnostics, PackedStringArray([
		"model 7 part 0 hilite 0: type 1 starts no supported particle generator; omitted",
		"model 7 part 0 hilite 1: type 7 starts no supported particle generator; omitted",
		"model 7 part 0 hilite 2: type 12 starts no supported particle generator; omitted",
		"model 7 part 0 hilite 3: attach type 2 is not a vertex; omitted",
	]))

func test_borrowed_parts_carry_their_counterpart_hilites() -> void:
	var counterpart: MofPart = _part(0, [_hilite(3, MofPart.ATTACH_VERTEX, 6)])
	var borrowed: MofPart = _part(0, [])
	borrowed.hilite_count = 1
	borrowed.borrow_from(counterpart)
	var diagnostics := PackedStringArray()
	assert_eq(_texts(EffectSetup.hilites_of(_model([[borrowed]]), ExeParticleGenerators.C_SPECIAL_GENERATORS, "model", diagnostics)), PackedStringArray(["EXHAUST:0:6"]))
	assert_eq(EffectSetup.hilites_of(null, ExeParticleGenerators.C_SPECIAL_GENERATORS, "model", diagnostics).size(), 0)
	assert_eq(EffectSetup.hilites_of(MofFile.new(), ExeParticleGenerators.C_SPECIAL_GENERATORS, "model", diagnostics).size(), 0)

func test_kind_names_and_missing_data() -> void:
	assert_eq([EffectSetup.kind_for_generator("PGIN_hilite_exhaust"), EffectSetup.kind_for_generator("PGIN_hilite_dust"), EffectSetup.kind_for_generator("PGIN_hilite_fire")], [ParticleHilite.Kind.EXHAUST, ParticleHilite.Kind.DUST, ParticleHilite.Kind.FIRE])
	assert_eq(EffectSetup.kind_for_generator("PGIN_frog_on_fire"), -1)
	var definition := EntityDefinition.new()
	definition.particle_hilites.append(ParticleHilite.new())
	var definitions: Array[EntityDefinition] = [definition]
	var diagnostics := PackedStringArray()
	EffectSetup.resolve_hilites(null, 1, definitions, diagnostics)
	assert_eq([definition.particle_hilites.size(), diagnostics.size()], [1, 0], "Without player data nothing changes")
