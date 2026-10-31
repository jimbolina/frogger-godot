class_name ExeParticleGeneratorsReader
extends RefCounted
## Locates and names the particle generator records, tables and pop colours
## ([ExeParticleGenerators]) by their shape in the program bytes.


## Locates and names the records of [param exe], resolving textures through [param bmp].
static func read(exe: ExeImage, bmp: BmpPointers) -> ExeParticleGenerators:
	var result := ExeParticleGenerators.new()
	if exe == null or not exe.is_valid() or bmp == null or not bmp.error.is_empty():
		result.warnings.append("Particle generators need a readable executable and texture pointer list")
		return result
	var words: PackedInt64Array = program_words(exe)
	var by_address: Dictionary[int, ParticleGeneratorRecord] = {}
	var found: Array[ParticleGeneratorRecord] = []
	for index: int in words.size() - ParticleGeneratorRecord.WORDS:
		var record: ParticleGeneratorRecord = record_from_words(words, index)
		if record == null:
			continue
		record.address = exe.offset_to_pointer(index * 4)
		found.append(record)
		by_address[record.address] = record
	if found.is_empty():
		result.warnings.append("No particle generator records were found in the executable")
		return result
	var problem: String = _name_records(result, exe, words, found, by_address)
	if not problem.is_empty():
		result.warnings.append(problem + "; using the frozen C particle generators")
		result.special_generators.clear()
		result.frog_particle_flags.clear()
		result.frog_particle_single.clear()
		result.frog_particle_multi.clear()
		return result
	for record: ParticleGeneratorRecord in found:
		_resolve_textures(result, exe, bmp, record)
	result.records = found
	result.from_executable = true
	_read_pop_colours(result, exe, words, found)
	return result


## The program bytes of [param exe] as unsigned little-endian words, one per aligned file offset.
static func program_words(exe: ExeImage) -> PackedInt64Array:
	var length: int = exe.program_length - exe.program_length % 4
	var signed: PackedInt32Array = exe.bytes.slice(0, length).to_int32_array()
	var result := PackedInt64Array()
	result.resize(signed.size())
	for index: int in signed.size():
		result[index] = signed[index] & 0xFFFFFFFF
	return result


## The record ([ParticleGeneratorRecord]) whose first word is
## [param words][[param index]] (program words as unsigned values), or null
## when it does not have the generator shape.
static func record_from_words(words: PackedInt64Array, index: int) -> ParticleGeneratorRecord:
	if index < 0 or index + ParticleGeneratorRecord.WORDS > words.size():
		return null
	var first: int = words[index]
	if first & 0xFFFF != ParticleGeneratorRecord.TYPE_2D or words[index + 1] < 16 or words[index + 1] > 80:
		return null
	var record := ParticleGeneratorRecord.new()
	record.type = first & 0xFFFF
	record.flags = first >> 16
	record.prim_size = words[index + 1]
	record.geometry_init = words[index + 2]
	record.prim_init = words[index + 3]
	record.move = words[index + 4]
	record.display = words[index + 5]
	if not record.has_generator_shape():
		return null
	record.gravity_16 = _signed(words[index + 6], 32)
	record.max_particles = words[index + 7] & 0xFFFF
	record.generator_life = _signed(words[index + 7] >> 16, 16)
	record.particle_min_life = words[index + 8] & 0xFFFF
	record.particle_max_life = words[index + 8] >> 16
	record.user_data_1 = words[index + 9]
	record.user_data_2 = words[index + 10]
	return record


static func _name_records(result: ExeParticleGenerators, exe: ExeImage, words: PackedInt64Array,
		found: Array[ParticleGeneratorRecord], by_address: Dictionary[int, ParticleGeneratorRecord]) -> String:
	var special_at: int = -1
	var frog_at: int = -1
	var frog_flags: PackedInt32Array = ExeParticleGenerators.C_FROG_PARTICLE_FLAGS
	for index: int in words.size() - ExeParticleGenerators.TABLE_WORDS:
		if words[index + 3] == 0 or (words[index + 3] != words[index + 4] and words[index] != frog_flags[0]):
			continue
		if words[index] == 0 and words[index + 1] == 0 and words[index + 2] == 0 and words[index + 7] == 0 and words[index + 8] == 0 \
				and words[index + 3] == words[index + 4] and by_address.has(words[index + 4]) and by_address.has(words[index + 5]) and by_address.has(words[index + 6]) \
				and words[index + 4] != words[index + 5] and words[index + 5] != words[index + 6] and words[index + 4] != words[index + 6]:
			if special_at >= 0:
				return "More than one Entity_special_particle_generators table"
			special_at = index
		if words[index] == frog_flags[0] and words[index + 3] == frog_flags[1] and words[index + 6] == frog_flags[2] \
				and words[index + 1] == words[index + 2] and words[index + 5] == 0 and words[index + 8] == 0 \
				and by_address.has(words[index + 1]) and by_address.has(words[index + 4]) and by_address.has(words[index + 7]):
			if frog_at >= 0:
				return "More than one Frog_particle_effects table"
			frog_at = index
	if special_at < 0:
		return "Entity_special_particle_generators was not found"
	if frog_at < 0:
		return "Frog_particle_effects was not found"
	result.special_table_address = exe.offset_to_pointer(special_at * 4)
	result.frog_table_address = exe.offset_to_pointer(frog_at * 4)
	var special_names: PackedStringArray = ExeParticleGenerators.C_SPECIAL_GENERATORS
	var single_names: PackedStringArray = ExeParticleGenerators.C_FROG_PARTICLE_SINGLE
	for slot: int in ExeParticleGenerators.TABLE_WORDS:
		var record: ParticleGeneratorRecord = by_address.get(words[special_at + slot], null)
		if record != null and special_names[slot] != "" and record.name.is_empty():
			record.name = special_names[slot]
	for slot: int in single_names.size():
		var single: ParticleGeneratorRecord = by_address[words[frog_at + 3 * slot + 1]]
		single.name = single_names[slot]
	var reference: ExeParticleGenerators = ExeParticleGenerators.c_constants()
	var last: int = 0
	for c: ParticleGeneratorRecord in reference.records:
		var named: ParticleGeneratorRecord = null
		for record: ParticleGeneratorRecord in found:
			if record.name == c.name:
				named = record
				break
		if named != null:
			last = named.address
			continue
		for record: ParticleGeneratorRecord in found:
			if record.name.is_empty() and record.address > last and record.flags == c.flags and record.max_particles == c.max_particles \
					and record.generator_life == c.generator_life and record.user_data_1 == c.user_data_1:
				named = record
				break
		if named == null:
			return "No particle generator record matches %s" % c.name
		named.name = c.name
		last = named.address
	var counts: Dictionary[String, int] = {}
	for record: ParticleGeneratorRecord in found:
		if not record.name.is_empty():
			var count: int = counts.get(record.name, 0)
			counts[record.name] = count + 1
	for c: ParticleGeneratorRecord in reference.records:
		var assigned: int = counts.get(c.name, 0)
		if assigned != 1:
			return "Particle generator %s is not assigned exactly once" % c.name
	for slot: int in ExeParticleGenerators.TABLE_WORDS:
		var record: ParticleGeneratorRecord = by_address.get(words[special_at + slot], null)
		result.special_generators.append(record.name if record != null else "")
	for slot: int in single_names.size():
		result.frog_particle_flags.append(words[frog_at + 3 * slot])
		var single: ParticleGeneratorRecord = by_address[words[frog_at + 3 * slot + 1]]
		var multi: ParticleGeneratorRecord = by_address.get(words[frog_at + 3 * slot + 2], null)
		result.frog_particle_single.append(single.name)
		result.frog_particle_multi.append(multi.name if multi != null else "")
	return ""


static func _resolve_textures(result: ExeParticleGenerators, exe: ExeImage, bmp: BmpPointers, record: ParticleGeneratorRecord) -> void:
	var value: int = record.user_data_2
	if value == 0 or not ExeImage.looks_like_pointer(value):
		return
	var single: int = bmp.texture_id_for_pointer(value)
	if single >= 0:
		record.texture_kind = ParticleGeneratorRecord.TextureKind.TEXTURE
		record.texture_ids.append(single)
		return
	var reader: ByteReader = exe.reader_at_pointer(value)
	var ids := PackedInt32Array()
	for slot: int in ExeParticleGenerators.MAX_LIST_TEXTURES:
		var pointer: int = reader.read_u32()
		if reader.has_error():
			break
		if pointer == 0:
			if ids.is_empty():
				break
			record.texture_kind = ParticleGeneratorRecord.TextureKind.TEXTURE_LIST
			record.texture_ids = ids
			return
		var id: int = bmp.texture_id_for_pointer(pointer)
		if id < 0:
			break
		ids.append(id)
	if not record.name.is_empty():
		result.warnings.append("%s user data 2 0x%X is not a texture list" % [record.name, value])


static func _read_pop_colours(result: ExeParticleGenerators, exe: ExeImage, words: PackedInt64Array, found: Array[ParticleGeneratorRecord]) -> void:
	var c_colours: PackedInt64Array = ExeParticleGenerators.C_POP_COLOURS
	var octagon: PackedInt32Array = ExeParticleGenerators.EXPLOSION_OCTAGON
	result.pop_colours = c_colours.duplicate()
	var fire: ParticleGeneratorRecord = result.find("PGIN_hilite_fire")
	var stride: int = -1
	for index: int in range(1, found.size()):
		var gap: int = found[index].address - found[index - 1].address
		if stride < 0 or gap < stride:
			stride = gap
	if fire == null or stride <= 0:
		result.warnings.append("Frog_pop_explosion_colours cannot be placed; using the frozen C colours")
		return
	var colours_at: int = exe.pointer_to_offset(fire.address + stride)
	var octagon_at: int = (colours_at + c_colours.size() * 4 + 7) & ~7
	if colours_at % 4 != 0 or not exe.contains(colours_at, c_colours.size() * 4) or not exe.contains(octagon_at, 4 * octagon.size()):
		result.warnings.append("Frog_pop_explosion_colours lie outside the program; using the frozen C colours")
		return
	for point: int in octagon.size() >> 1:
		if exe.bytes.decode_s16(octagon_at + 8 * point) != octagon[2 * point] or exe.bytes.decode_s16(octagon_at + 8 * point + 2) != octagon[2 * point + 1]:
			result.warnings.append("Explosion_offsets_octagon does not follow the pop colours; using the frozen C colours")
			return
	var colours := PackedInt64Array()
	for player: int in c_colours.size():
		colours.append(words[(colours_at >> 2) + player])
	result.pop_colours = colours


static func _signed(value: int, bits: int) -> int:
	return value - (1 << bits) if value & (1 << (bits - 1)) else value
