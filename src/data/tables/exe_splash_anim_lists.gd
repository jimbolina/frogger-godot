class_name ExeSplashAnimLists
extends Resource
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
@export var lists: Array[PackedInt32Array] = []
## In-program address of each list found.
@export var addresses: PackedInt64Array = PackedInt64Array()
## Why a list was rejected or the lists disagree; empty when they read cleanly.
@export var warnings: PackedStringArray = PackedStringArray()


## The six ripple texture ids every found list shows, or empty when there is
## no list or the lists disagree.
func ripple_texture_ids() -> PackedInt32Array:
	if lists.is_empty():
		return PackedInt32Array()
	for ids: PackedInt32Array in lists:
		if ids != lists[0]:
			return PackedInt32Array()
	return lists[0].duplicate()
