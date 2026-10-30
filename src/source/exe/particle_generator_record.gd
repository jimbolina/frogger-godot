class_name ParticleGeneratorRecord
extends RefCounted
## One particle generator initialiser ([code]MR_PGEN_INIT[/code], [code]MR_PART.H:51-69[/code]).
##
## Layout, 44 bytes:
## [codeblock]
## u16 type   u16 flags   u32 prim size
## u32 geometry init   u32 prim init   u32 move   u32 display   (callback addresses)
## s32 gravity (16.16)
## u16 max particles   s16 generator life (-1 = infinite)
## u16 particle min life   u16 particle max life
## u32 user data 1   u32 user data 2
## [/codeblock]
## The texture a generator draws is usually [member user_data_2]: the address
## of one texture record, or of a NULL-terminated list of them.

## How [member user_data_2] names textures.
enum TextureKind { NONE, TEXTURE, TEXTURE_LIST }

## Source MR_PTYPE_2D.
const TYPE_2D: int = 2
## Source MR_PF_NO_GEOMETRY.
const FLAG_NO_GEOMETRY: int = 0x10
## Size of the stored record.
const SIZE: int = 44
## Size of the stored record in 32-bit words.
const WORDS: int = 11

## Source initialiser name, or "" for a record without one.
var name: String = ""
## In-program address of the record, or -1 for a frozen C constant.
var address: int = -1
var type: int = TYPE_2D
var flags: int = 0
var prim_size: int = 0
## Callback addresses; zero for frozen C constants.
var geometry_init: int = 0
var prim_init: int = 0
var move: int = 0
var display: int = 0
## Signed 16.16 gravity.
var gravity_16: int = 0
var max_particles: int = 0
## Signed; -1 is infinite.
var generator_life: int = 0
var particle_min_life: int = 0
var particle_max_life: int = 0
var user_data_1: int = 0
var user_data_2: int = 0
var texture_kind: TextureKind = TextureKind.NONE
## Texture ids resolved from [member user_data_2] in list order (executable records).
var texture_ids: PackedInt32Array = PackedInt32Array()
## Source image symbols named by [member user_data_2] (frozen C constants).
var texture_symbols: PackedStringArray = PackedStringArray()


## The record whose first word is [param words][[param index]] (program words
## as unsigned values), or null when it does not have the generator shape
## (2D type, flags 0 or no-geometry, a 16-80 byte primitive and program
## addresses for the prim-init, move and display callbacks).
static func from_words(words: PackedInt64Array, index: int) -> ParticleGeneratorRecord:
	if index < 0 or index + WORDS > words.size():
		return null
	var first: int = words[index]
	if first & 0xFFFF != TYPE_2D or words[index + 1] < 16 or words[index + 1] > 80:
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


## True for the generator shape [method read_shaped] accepts.
func has_generator_shape() -> bool:
	if type != TYPE_2D or flags not in [0, FLAG_NO_GEOMETRY] or prim_size < 16 or prim_size > 80:
		return false
	for pointer: int in [prim_init, move, display]:
		if not ExeImage.looks_like_pointer(pointer):
			return false
	return geometry_init == 0 or ExeImage.looks_like_pointer(geometry_init)


## The fields that differ from [param reference] (flags, counts, lifetimes,
## gravity, user data 1, then textures), with [param symbol_ids] turning the
## reference's image symbols into texture ids.
func differences_from(reference: ParticleGeneratorRecord, symbol_ids: Dictionary[String, int]) -> PackedStringArray:
	var result := PackedStringArray()
	for field: String in ["flags", "max_particles", "generator_life", "particle_min_life", "particle_max_life", "gravity_16", "user_data_1"]:
		if get(field) != reference.get(field):
			result.append(field)
	var expected := PackedInt32Array()
	for symbol: String in reference.texture_symbols:
		var id: int = symbol_ids.get(symbol, -1)
		expected.append(id)
	if expected != texture_ids:
		result.append("texture")
	return result


static func _signed(value: int, bits: int) -> int:
	return value - (1 << bits) if value & (1 << (bits - 1)) else value
