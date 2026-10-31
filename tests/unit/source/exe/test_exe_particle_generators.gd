extends GutTest
## Particle generator records, generator tables, pop colours and splash lists located in synthetic executables.

const P: int = SyntheticExe.RAM_OFFSET
const TEXTURES_AT: int = 0x100
const BMP_AT: int = 0x200
const DUST_LIST_AT: int = 0x300
const FIRST_GROUP_AT: int = 0x400
const SECOND_GROUP_AT: int = 0x900
const SPECIAL_AT: int = 0xC00
const FROG_AT: int = 0xC40
const SPLASH_AT: PackedInt32Array = [0xD00, 0xE00]
const CALLBACK: int = 0x2F00 + P
const STRIDE: int = 0x30
const FIRST_GROUP: PackedStringArray = ["PGIN_for_swarm", "PGIN_for_swarm_multiplayer", "PGIN_pickup", "PGIN_pickup_explosion", "", "PGIN_frog_pop_explosion", "PGIN_hilite_exhaust", "PGIN_hilite_dust", "PGIN_hilite_fire"]
const SECOND_GROUP: PackedStringArray = ["PGIN_frog_slip_effect", "PGIN_frog_water_bubble", "PGIN_frog_on_fire", "PGIN_stone_to_gold_frog", "PGIN_gold_frog_glow"]
const TEXTURE_BY_GENERATOR: Dictionary[String, int] = {
	"PGIN_for_swarm": 1, "PGIN_for_swarm_multiplayer": 1, "PGIN_hilite_exhaust": 2, "PGIN_hilite_fire": 5,
	"PGIN_frog_slip_effect": 5, "PGIN_frog_water_bubble": 6, "PGIN_frog_on_fire": 5, "PGIN_stone_to_gold_frog": 5,
}

var _addresses: Dictionary[String, int] = {}

func _texture(id: int) -> int:
	return TEXTURES_AT + 16 * id + P

func _write_record(s: SyntheticExe, at: int, generator_name: String) -> void:
	var c: ParticleGeneratorRecord = ExeParticleGenerators.c_constants().find(generator_name)
	var flags: int = c.flags if c != null else ParticleGeneratorRecord.FLAG_NO_GEOMETRY
	var max_particles: int = c.max_particles if c != null else 10
	var life: int = c.generator_life if c != null else 30
	var min_life: int = c.particle_min_life if c != null else 0
	var max_life: int = c.particle_max_life if c != null else 0
	var gravity: int = c.gravity_16 if c != null else 0
	var user1: int = c.user_data_1 if c != null else 0xC00
	if generator_name == "PGIN_hilite_fire":
		min_life = 30
		max_life = 40
	var user2: int = 0
	if TEXTURE_BY_GENERATOR.has(generator_name):
		user2 = _texture(TEXTURE_BY_GENERATOR[generator_name])
	elif generator_name == "PGIN_hilite_dust":
		user2 = DUST_LIST_AT + P
	s.bytes.encode_u16(at, ParticleGeneratorRecord.TYPE_2D)
	s.bytes.encode_u16(at + 2, flags)
	s.s32s(at + 4, [48, 0, CALLBACK, CALLBACK + 4, CALLBACK + 8, gravity])
	s.bytes.encode_u16(at + 28, max_particles)
	s.bytes.encode_s16(at + 30, life)
	s.bytes.encode_u16(at + 32, min_life)
	s.bytes.encode_u16(at + 34, max_life)
	s.s32s(at + 36, [user1, user2])
	_addresses[generator_name] = at + P

func _splash(s: SyntheticExe, at: int, ids: PackedInt32Array) -> void:
	var words: Array[int] = [0, 0, 0, 0, 3, 2, 4, 8 << 16]
	for id: int in ids:
		words.append_array([1, _texture(id)])
	for grey: int in [0x606060, 0x404040, 0x202020]:
		words.append_array([5, grey, 1, _texture(ids[ids.size() - 1])])
	words.append(16)
	s.s32s(at, words)

func _exe(with_octagon: bool = true) -> SyntheticExe:
	_addresses.clear()
	var s := SyntheticExe.new(0x3000)
	var pointers: Array[int] = []
	for id: int in 8:
		pointers.append(_texture(id))
	s.s32s(BMP_AT, pointers)
	s.version.bmp_pointer_address = BMP_AT
	s.s32s(DUST_LIST_AT, [_texture(3), _texture(4), 0])
	for slot: int in FIRST_GROUP.size():
		_write_record(s, FIRST_GROUP_AT + STRIDE * slot, FIRST_GROUP[slot])
	var colours_at: int = FIRST_GROUP_AT + STRIDE * FIRST_GROUP.size()
	s.s32s(colours_at, [0x000401, 0x040004, 0x000404, 0x040400, 0x000104])
	if with_octagon:
		var octagon_at: int = (colours_at + 20 + 7) & ~7
		var values: PackedInt32Array = ExeParticleGenerators.EXPLOSION_OCTAGON
		for point: int in values.size() >> 1:
			s.s16s(octagon_at + 8 * point, [values[2 * point], values[2 * point + 1], 0, 0])
	for slot: int in SECOND_GROUP.size():
		_write_record(s, SECOND_GROUP_AT + STRIDE * slot, SECOND_GROUP[slot])
	var exhaust: int = _addresses["PGIN_hilite_exhaust"]
	s.s32s(SPECIAL_AT, [0, 0, 0, exhaust, exhaust, _addresses["PGIN_hilite_dust"], _addresses["PGIN_hilite_fire"], 0, 0])
	var slip: int = _addresses["PGIN_frog_slip_effect"]
	s.s32s(FROG_AT, [0x300, slip, slip, 0x200, _addresses["PGIN_frog_water_bubble"], 0, 0x200, _addresses["PGIN_frog_on_fire"], 0])
	_splash(s, SPLASH_AT[0], PackedInt32Array([7, 3, 4, 5, 6, 2]))
	_splash(s, SPLASH_AT[1], PackedInt32Array([7, 3, 4, 5, 6, 2]))
	return s

func _read(s: SyntheticExe) -> ExeParticleGenerators:
	var exe: ExeImage = ExeImage.create(s.bytes, s.version)
	return ExeParticleGeneratorsReader.read(exe, BmpPointersReader.read(exe))

func test_records_are_named_from_both_tables_then_the_c_declaration_order() -> void:
	var s: SyntheticExe = _exe()
	var generators: ExeParticleGenerators = _read(s)
	assert_eq(generators.warnings, PackedStringArray())
	assert_true(generators.from_executable)
	assert_eq(generators.records.size(), FIRST_GROUP.size() + SECOND_GROUP.size())
	for generator_name: String in _addresses:
		if generator_name.is_empty():
			continue
		var record: ParticleGeneratorRecord = generators.find(generator_name)
		assert_not_null(record, generator_name)
		if record != null:
			assert_eq(record.address, _addresses[generator_name], generator_name)
	assert_eq(generators.records[4].name, "", "The record without a C initialiser stays unnamed")
	assert_eq(generators.records[4].user_data_1, 0xC00)
	assert_eq(generators.special_generators, PackedStringArray(["", "", "", "PGIN_hilite_exhaust", "PGIN_hilite_exhaust", "PGIN_hilite_dust", "PGIN_hilite_fire", "", ""]))
	assert_eq(generators.frog_particle_flags, PackedInt32Array([0x300, 0x200, 0x200]))
	assert_eq(generators.frog_particle_single, PackedStringArray(["PGIN_frog_slip_effect", "PGIN_frog_water_bubble", "PGIN_frog_on_fire"]))
	assert_eq(generators.frog_particle_multi, PackedStringArray(["PGIN_frog_slip_effect", "", ""]))
	assert_eq(generators.special_table_address, SPECIAL_AT + P)
	assert_eq(generators.frog_table_address, FROG_AT + P)
	assert_eq(generators.for_hilite_type(5).name, "PGIN_hilite_dust")
	assert_null(generators.for_hilite_type(0))

func test_records_keep_stored_values_and_resolve_texture_words() -> void:
	var generators: ExeParticleGenerators = _read(_exe())
	var fire: ParticleGeneratorRecord = generators.find("PGIN_hilite_fire")
	assert_eq([fire.particle_min_life, fire.particle_max_life, fire.gravity_16, fire.user_data_1, fire.prim_size], [30, 40, -65536, 70 << 10, 48])
	assert_eq([fire.texture_kind, fire.texture_ids], [ParticleGeneratorRecord.TextureKind.TEXTURE, PackedInt32Array([5])])
	var dust: ParticleGeneratorRecord = generators.find("PGIN_hilite_dust")
	assert_eq([dust.texture_kind, dust.texture_ids], [ParticleGeneratorRecord.TextureKind.TEXTURE_LIST, PackedInt32Array([3, 4])])
	var pickup: ParticleGeneratorRecord = generators.find("PGIN_pickup")
	assert_eq([pickup.texture_kind, pickup.texture_ids, pickup.generator_life], [ParticleGeneratorRecord.TextureKind.NONE, PackedInt32Array(), -1])
	var reference: ParticleGeneratorRecord = ExeParticleGenerators.c_constants().find("PGIN_hilite_fire")
	var ids: Dictionary[String, int] = {"im_frog_smoke1": 5}
	assert_eq(fire.differences_from(reference, ids), PackedStringArray(["particle_min_life", "particle_max_life"]))
	ids["im_frog_smoke1"] = 4
	assert_eq(fire.differences_from(reference, ids), PackedStringArray(["particle_min_life", "particle_max_life", "texture"]))

func test_pop_colours_follow_the_fire_record_when_the_octagon_anchors_them() -> void:
	assert_eq(_read(_exe()).pop_colours, PackedInt64Array([0x000401, 0x040004, 0x000404, 0x040400, 0x000104]))
	var unanchored: ExeParticleGenerators = _read(_exe(false))
	assert_true(unanchored.from_executable)
	assert_eq(unanchored.pop_colours, ExeParticleGenerators.C_POP_COLOURS)
	assert_eq(unanchored.warnings.size(), 1)

func test_unrecognised_tables_leave_no_records_and_a_warning() -> void:
	var s: SyntheticExe = _exe()
	s.s32s(FROG_AT, [0x301])
	var no_frog: ExeParticleGenerators = _read(s)
	assert_false(no_frog.from_executable)
	assert_eq(no_frog.records.size(), 0)
	assert_eq(no_frog.special_generators.size(), 0)
	assert_eq(no_frog.warnings.size(), 1)
	s = _exe()
	s.s32s(SPECIAL_AT + 16, [_addresses["PGIN_hilite_dust"]])
	var reshaped: ExeParticleGenerators = _read(s)
	assert_false(reshaped.from_executable, "A table whose shape changed is not recognised")
	assert_eq(reshaped.warnings.size(), 1)
	var empty: ExeParticleGenerators = _read(SyntheticExe.new(0x400))
	assert_eq([empty.records.size(), empty.warnings.size()], [0, 1])

func test_c_constants_list_every_initialiser_in_declaration_order() -> void:
	var constants: ExeParticleGenerators = ExeParticleGenerators.c_constants()
	var names := PackedStringArray()
	for record: ParticleGeneratorRecord in constants.records:
		names.append(record.name)
	assert_eq(names, PackedStringArray(["PGIN_for_swarm", "PGIN_for_swarm_multiplayer", "PGIN_pickup", "PGIN_pickup_explosion", "PGIN_frog_pop_explosion", "PGIN_hilite_exhaust", "PGIN_hilite_dust", "PGIN_hilite_fire", "PGIN_frog_slip_effect", "PGIN_frog_water_bubble", "PGIN_frog_on_fire", "PGIN_stone_to_gold_frog", "PGIN_gold_frog_glow"]))
	assert_false(constants.from_executable)
	assert_eq(constants.pop_colours, ExeParticleGenerators.C_POP_COLOURS)
	assert_eq(constants.find("PGIN_hilite_exhaust").texture_symbols, PackedStringArray(["im_tongue_tip"]))

func test_splash_lists_give_the_shared_ripple_images() -> void:
	var s: SyntheticExe = _exe()
	var exe: ExeImage = ExeImage.create(s.bytes, s.version)
	var splash: ExeSplashAnimLists = ExeSplashAnimListsReader.read(exe, BmpPointersReader.read(exe))
	assert_eq(splash.warnings, PackedStringArray())
	assert_eq(splash.addresses, PackedInt64Array([SPLASH_AT[0] + P, SPLASH_AT[1] + P]))
	assert_eq(splash.ripple_texture_ids(), PackedInt32Array([7, 3, 4, 5, 6, 2]))
	s.s32s(SPLASH_AT[1] + 4 * 8 + 4 * 13, [0x707070])
	exe = ExeImage.create(s.bytes, s.version)
	var broken: ExeSplashAnimLists = ExeSplashAnimListsReader.read(exe, BmpPointersReader.read(exe))
	assert_eq(broken.lists.size(), 1)
	assert_eq(broken.warnings.size(), 1, "A list with another command shape is rejected")
	assert_eq(broken.ripple_texture_ids(), PackedInt32Array([7, 3, 4, 5, 6, 2]))
	_splash(s, SPLASH_AT[1], PackedInt32Array([7, 3, 4, 5, 6, 1]))
	exe = ExeImage.create(s.bytes, s.version)
	var disagreeing: ExeSplashAnimLists = ExeSplashAnimListsReader.read(exe, BmpPointersReader.read(exe))
	assert_eq(disagreeing.ripple_texture_ids(), PackedInt32Array(), "Lists showing different ripples give none")
	assert_eq(disagreeing.warnings.size(), 1)
	exe = ExeImage.create(SyntheticExe.new(0x400).bytes, s.version)
	var none: ExeSplashAnimLists = ExeSplashAnimListsReader.read(exe, BmpPointersReader.read(exe))
	assert_eq([none.lists.size(), none.warnings.size()], [0, 1])
