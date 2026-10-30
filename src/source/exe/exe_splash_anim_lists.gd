class_name ExeSplashAnimLists
extends RefCounted
## The water splash sprite animation lists the executable holds and the ripple images they show.
##
## Frozen [code]COLLIDE.C:43-65[/code] [code]FrogSplashAnimList[/code] and
## [code]scripter.c:31-55[/code] [code]TurtleSplashAnimList[/code] are
## [code]MR_SPRT[/code] command words: four NOPs, SETSPEED 2, SETSCALE 8<<16,
## six SETIMAGE ripple images, then SETCOLOUR 0x606060, 0x404040 and 0x202020,
## each followed by SETIMAGE of the last ripple, and KILL. The version file
## names no address for them, so [method read] finds every aligned word run
## with that fixed prefix and checks the rest of the command shape; the image
## words are texture record addresses resolved through [BmpPointers].
##
## FrogLord's PC image list carries the ripple names only as comments, so
## these lists are the ripple images' only source. When none is found (an
## unrecognised build), [method ripple_texture_ids] is empty and
## [member warnings] says why; splash effects then degrade.

## Source MR_SPRT opcodes.
const OP_NOP: int = 0
const OP_SETIMAGE: int = 1
const OP_SETSPEED: int = 3
const OP_SETSCALE: int = 4
const OP_SETCOLOUR: int = 5
const OP_KILL: int = 16
## The fixed command words that start both lists.
const PREFIX: PackedInt64Array = [OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_SETSPEED, 2, OP_SETSCALE, 8 << 16]
## Number of ripple images.
const IMAGES: int = 6
## Fading greys after the ripple images.
const FADES: PackedInt64Array = [0x606060, 0x404040, 0x202020]

## Ripple texture ids of each list found, in address order.
var lists: Array[PackedInt32Array] = []
## In-program address of each list found.
var addresses: PackedInt64Array = PackedInt64Array()
## Why a list was rejected or the lists disagree; empty when they read cleanly.
var warnings: PackedStringArray = PackedStringArray()


## Finds the splash lists of [param exe], resolving images through [param bmp].
static func read(exe: ExeImage, bmp: BmpPointers) -> ExeSplashAnimLists:
	var result := ExeSplashAnimLists.new()
	if exe == null or not exe.is_valid() or bmp == null or not bmp.error.is_empty():
		result.warnings.append("Splash animation lists need a readable executable and texture pointer list")
		return result
	var words: PackedInt64Array = ExeParticleGenerators.program_words(exe)
	var length: int = PREFIX.size() + 2 * IMAGES + 2 * FADES.size() * 2 + 1
	for index: int in words.size() - length:
		if words[index + 7] != PREFIX[7] or words[index + 6] != PREFIX[6]:
			continue
		var matches: bool = true
		for slot: int in PREFIX.size():
			if words[index + slot] != PREFIX[slot]:
				matches = false
				break
		if not matches:
			continue
		var ids: PackedInt32Array = _ripples(words, index + PREFIX.size(), bmp)
		var address: int = exe.offset_to_pointer(index * 4)
		if ids.is_empty():
			result.warnings.append("Splash animation list at 0x%X does not have the frozen command shape" % address)
			continue
		result.lists.append(ids)
		result.addresses.append(address)
	if result.lists.is_empty():
		result.warnings.append("No splash animation list was found in the executable")
	for ids: PackedInt32Array in result.lists:
		if ids != result.lists[0]:
			result.warnings.append("The splash animation lists show different ripple images")
			break
	return result


## The six ripple texture ids every found list shows, or empty when there is
## no list or the lists disagree.
func ripple_texture_ids() -> PackedInt32Array:
	if lists.is_empty():
		return PackedInt32Array()
	for ids: PackedInt32Array in lists:
		if ids != lists[0]:
			return PackedInt32Array()
	return lists[0].duplicate()


static func _ripples(words: PackedInt64Array, at: int, bmp: BmpPointers) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for slot: int in IMAGES:
		if words[at + 2 * slot] != OP_SETIMAGE:
			return PackedInt32Array()
		var id: int = bmp.texture_id_for_pointer(words[at + 2 * slot + 1])
		if id < 0:
			return PackedInt32Array()
		ids.append(id)
	var last: int = words[at + 2 * IMAGES - 1]
	var cursor: int = at + 2 * IMAGES
	for fade: int in FADES:
		if words[cursor] != OP_SETCOLOUR or words[cursor + 1] != fade or words[cursor + 2] != OP_SETIMAGE or words[cursor + 3] != last:
			return PackedInt32Array()
		cursor += 4
	if words[cursor] != OP_KILL:
		return PackedInt32Array()
	return ids
