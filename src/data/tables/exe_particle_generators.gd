class_name ExeParticleGenerators
extends Resource
## The particle generator initialisers, generator tables and pop colours the executable holds.
##
## The build's version file names no address for these, so [method read]
## finds them by shape in the program bytes, as the independent golden
## generator does. Every 4-byte-aligned file offset is tried as an
## [code]MR_PGEN_INIT[/code] ([ParticleGeneratorRecord]). Records are then
## named in three steps:
## [br]1. [code]Entity_special_particle_generators[/code], nine words
## [code]0, 0, 0, a, a, b, c, 0, 0[/code] with distinct record addresses
## [code]a[/code], [code]b[/code] and [code]c[/code], names the hilite
## exhaust, dust and fire records (frozen [code]ENTITY.C:71-81[/code]).
## [br]2. [code]Frog_particle_effects[/code], three
## [code]flags, single, multi[/code] triples with flags 0x300, 0x200 and
## 0x200, names the slip, water bubble and on-fire records.
## [br]3. The others take the frozen [code]PARTICLE.C[/code] declaration
## order: each name goes to the first unnamed record after the previous named
## one whose flags, maximum particles, generator life and user data 1 equal
## the C initialiser's.
## [br]A record matching no C initialiser keeps an empty name. The retail
## executable holds one, an explosion-shaped record at 0x475E80.
##
## [code]Frog_pop_explosion_colours[/code] are the five words one record
## stride after the hilite fire record. They are accepted when
## [code]Explosion_offsets_octagon[/code] follows them at the next 8-byte
## boundary, which anchors the place.
##
## A FrogLord-saved executable is searched only within its original program
## bytes, so the appended build information is never read. Edited values in
## records or tables are read as stored, and a repointed table entry names
## the record it points to while the table keeps the shape above.
##
## When the records or either table cannot be located (an unrecognised
## build), [method read] returns no records and a warning; the port then uses
## [method c_constants], the frozen C initialisers. When only the pop colours
## cannot be anchored, they fall back to [constant C_POP_COLOURS] with a
## warning.
##
## The retail executable disagrees with the C in three records, and the port
## follows the executable: the hilite exhaust scale is 0x9400 with texture
## 1163, the hilite fire lifetimes are 30-40 with scale 75<<10, and the extra
## record above has no C name.

## Source Entity_special_particle_generators by MOF hilite type ("" = NULL).
const C_SPECIAL_GENERATORS: PackedStringArray = ["", "", "", "PGIN_hilite_exhaust", "PGIN_hilite_exhaust", "PGIN_hilite_dust", "PGIN_hilite_fire", "", ""]
## Source Frog_particle_effects flags: EFFECT_KILL_WHEN_FROG_DEAD|EFFECT_KILL_WHEN_FROG_RESET, then EFFECT_KILL_WHEN_FROG_RESET.
const C_FROG_PARTICLE_FLAGS: PackedInt32Array = [0x300, 0x200, 0x200]
## Source Frog_particle_effects single- and multiplayer generators ("" = NULL).
const C_FROG_PARTICLE_SINGLE: PackedStringArray = ["PGIN_frog_slip_effect", "PGIN_frog_water_bubble", "PGIN_frog_on_fire"]
const C_FROG_PARTICLE_MULTI: PackedStringArray = ["PGIN_frog_slip_effect", "", ""]
## Source Frog_pop_explosion_colours (green, magenta, yellow, cyan, baby-frog pink), red in the low byte.
const C_POP_COLOURS: PackedInt64Array = [0x000400, 0x040004, 0x000404, 0x040400, 0x000104]
## Source Explosion_offsets_octagon x, y pairs: eight outer then eight inner points.
const EXPLOSION_OCTAGON: PackedInt32Array = [
	0, -0x1000, 0x0b50, -0x0b50, 0x1000, 0, 0x0b50, 0x0b50, 0, 0x1000, -0x0b50, 0x0b50, -0x1000, 0, -0x0b50, -0x0b50,
	0, -0x0800, 0x05a8, -0x05a8, 0x0800, 0, 0x05a8, 0x05a8, 0, 0x0800, -0x05a8, 0x05a8, -0x0800, 0, -0x05a8, -0x05a8,
]
const TABLE_WORDS: int = 9
const MAX_LIST_TEXTURES: int = 64
const C_GRAVITY: int = -(1 << 16)

## Every generator-shaped record in address order (C constants for [method c_constants]).
@export var records: Array[ParticleGeneratorRecord] = []
## Generator name by MOF hilite type ("" = none), nine entries.
@export var special_generators: PackedStringArray = PackedStringArray()
## Frog_particle_effects flags and generator names ("" = none), three entries each.
@export var frog_particle_flags: PackedInt32Array = PackedInt32Array()
@export var frog_particle_single: PackedStringArray = PackedStringArray()
@export var frog_particle_multi: PackedStringArray = PackedStringArray()
## Pop ring colours by player, red in the low byte.
@export var pop_colours: PackedInt64Array = PackedInt64Array()
## True when the records come from the executable.
@export var from_executable: bool = false
## In-program addresses of the located tables, or -1.
@export var special_table_address: int = -1
@export var frog_table_address: int = -1
## Why something fell back or was skipped; empty when everything was read.
@export var warnings: PackedStringArray = PackedStringArray()


## The frozen PARTICLE.C initialisers in declaration order, the C hilite and
## frog particle tables and pop colours. Callback addresses and primitive
## sizes are zero; textures are source image symbols.
static func c_constants() -> ExeParticleGenerators:
	var result := ExeParticleGenerators.new()
	var rows: Array[Array] = [
		["PGIN_for_swarm", 0x10, 3, -1, 0, 0, 0, 0, ["im_for_swarm"]],
		["PGIN_for_swarm_multiplayer", 0x10, 1, -1, 0, 0, 0, 0, ["im_for_swarm"]],
		["PGIN_pickup", 0, 2, -1, 0, 0, 0, 0, []],
		["PGIN_pickup_explosion", 0x10, 10, 30, 0, 0, 0, 48 << 7, []],
		["PGIN_frog_pop_explosion", 0x10, 10, 30, 0, 0, 0, 48 << 7, []],
		["PGIN_hilite_exhaust", 0, 25, -1, 5, 8, C_GRAVITY, 64 << 9, ["im_tongue_tip"]],
		["PGIN_hilite_dust", 0, 14, -1, 12, 12, C_GRAVITY, 64 << 11, ["im_bison1", "im_bison2", "im_bison3", "im_bison4", "im_bison5", "im_bison6"]],
		["PGIN_hilite_fire", 0, 40, -1, 10, 20, C_GRAVITY, 70 << 10, ["im_frog_smoke1"]],
		["PGIN_frog_slip_effect", 0, 50, -1, 6, 12, C_GRAVITY, 96 << 10, ["im_frog_smoke1"]],
		["PGIN_frog_water_bubble", 0, 20, 90, 12, 12, C_GRAVITY, 64 << 9, ["im_wake2"]],
		["PGIN_frog_on_fire", 0, 150, -1, 40, 50, C_GRAVITY, 120 << 9, ["im_frog_smoke1"]],
		["PGIN_stone_to_gold_frog", 0, 100, 30, 15, 20, C_GRAVITY, 64 << 9, ["im_frog_smoke1"]],
		["PGIN_gold_frog_glow", 0, 1, -1, 0, 0, 0, 0, []],
	]
	for row: Array in rows:
		var record := ParticleGeneratorRecord.new()
		record.name = row[0]
		record.flags = row[1]
		record.max_particles = row[2]
		record.generator_life = row[3]
		record.particle_min_life = row[4]
		record.particle_max_life = row[5]
		record.gravity_16 = row[6]
		record.user_data_1 = row[7]
		var symbols: Array = row[8]
		for symbol: String in symbols:
			record.texture_symbols.append(symbol)
		if symbols.size() == 1:
			record.texture_kind = ParticleGeneratorRecord.TextureKind.TEXTURE
		elif symbols.size() > 1:
			record.texture_kind = ParticleGeneratorRecord.TextureKind.TEXTURE_LIST
		result.records.append(record)
	result.special_generators = C_SPECIAL_GENERATORS.duplicate()
	result.frog_particle_flags = C_FROG_PARTICLE_FLAGS.duplicate()
	result.frog_particle_single = C_FROG_PARTICLE_SINGLE.duplicate()
	result.frog_particle_multi = C_FROG_PARTICLE_MULTI.duplicate()
	result.pop_colours = C_POP_COLOURS.duplicate()
	return result


## The record called [param generator_name], or null.
func find(generator_name: String) -> ParticleGeneratorRecord:
	for record: ParticleGeneratorRecord in records:
		if record.name == generator_name:
			return record
	return null


## The record the MOF hilite type [param hilite_type] creates, or null.
func for_hilite_type(hilite_type: int) -> ParticleGeneratorRecord:
	if hilite_type < 0 or hilite_type >= special_generators.size() or special_generators[hilite_type].is_empty():
		return null
	return find(special_generators[hilite_type])
