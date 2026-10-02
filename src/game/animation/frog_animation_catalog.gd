class_name FrogAnimationCatalog
extends RefCounted
## Named action/script facts transcribed independently from frozen froganim.c and gen_frog.h.
## Regenerate with tools/make_golden_frog_animation.py --runtime-catalog; no retail bytes.

const AUTOHOP: int = 0
const BACKFLIP: int = 1
const SQUISHED: int = 2
const WAIT1: int = 3
const TIMEOUT: int = 4
const STRUGGLE: int = 5
const FALLING: int = 6
const TRIGGER: int = 7
const DROWN: int = 8
const COMPLETE: int = 9
const BITTEN: int = 10
const FREEFALL: int = 11
const FLOP: int = 12
const OUCH: int = 13
const PANT: int = 14
const ROLL: int = 15
const HOP: int = 16
const SUPERJUMP: int = 17
const PANT2: int = 18
const WAIT3: int = 19
const SUPERHOP: int = 20
const WAIT2: int = 21
const SLIP: int = 22
const POP: int = 23
const SLIPRIGHT: int = 24
const SLIPLEFT: int = 25
const CRASH: int = 26
const PHEW: int = 27
const LOOKDOWN: int = 28
const LOOKUP: int = 29
const LOOKLEFT: int = 30
const LOOKRIGHT: int = 31
const DANCE: int = 32
const MOWN: int = 33
const ROLL_REPEATING: int = 34

const NAMES: Array[StringName] = [&"AUTOHOP", &"BACKFLIP", &"SQUISHED", &"WAIT1", &"TIMEOUT", &"STRUGGLE", &"FALLING", &"TRIGGER", &"DROWN", &"COMPLETE", &"BITTEN", &"FREEFALL", &"FLOP", &"OUCH", &"PANT", &"ROLL", &"HOP", &"SUPERJUMP", &"PANT2", &"WAIT3", &"SUPERHOP", &"WAIT2", &"SLIP", &"POP", &"SLIPRIGHT", &"SLIPLEFT", &"CRASH", &"PHEW", &"LOOKDOWN", &"LOOKUP", &"LOOKLEFT", &"LOOKRIGHT", &"DANCE", &"MOWN", &"ROLL_REPEATING"]
const ACTION_NAMES: Array[StringName] = [&"GEN_FROG_AUTOHOP", &"GEN_FROG_BACKFLIP", &"GEN_FROG_SQUISHED", &"GEN_FROG_WAIT1", &"GEN_FROG_TIMEOUT", &"GEN_FROG_STRUGGLE", &"GEN_FROG_FALLING", &"GEN_FROG_TRIGGER", &"GEN_FROG_DROWN", &"GEN_FROG_COMPLETE", &"GEN_FROG_BITTEN", &"GEN_FROG_FREEFALL", &"GEN_FROG_FLOP", &"GEN_FROG_OUCH", &"GEN_FROG_PANT", &"GEN_FROG_ROLL", &"GEN_FROG_HOP", &"GEN_FROG_SUPERJUMP", &"GEN_FROG_PANT2", &"GEN_FROG_WAIT3", &"GEN_FROG_SUPERHOP", &"GEN_FROG_WAIT2", &"GEN_FROG_SLIP", &"GEN_FROG_POP", &"GEN_FROG_SLIPRIGHT", &"GEN_FROG_SLIPLEFT", &"GEN_FROG_CRASH", &"GEN_FROG_PHEW", &"GEN_FROG_LOOKDOWN", &"GEN_FROG_LOOKUP", &"GEN_FROG_LOOKLEFT", &"GEN_FROG_LOOKRIGHT", &"GEN_FROG_DANCE", &"GEN_FROG_MOWN"]
const FLAGS: Array[int] = [8, 8, 40, 2, 40, 8, 8, 8, 40, 8, 40, 8, 40, 8, 18, 8, 8, 8, 18, 8, 8, 8, 8, 40, 4, 4, 8, 2, 2, 2, 2, 2, 8, 8, 8]
const PROGRAMS: Array[Array] = [
	[0, 0, 0, 0, 5, 3],
	[0, 0, 0, 1, 5, 3],
	[0, 0, 0, 2, 4],
	[0, 0, 0, 3, 5, 3],
	[0, 0, 0, 4, 4],
	[0, 1, 0, 5, 4],
	[0, 1, 8, 6, 4],
	[0, 0, 0, 7, 5, 3],
	[0, 0, 0, 8, 4],
	[0, 0, 0, 9, 5, 3],
	[0, 0, 0, 10, 4],
	[0, 1, 5, 11, 4],
	[0, 0, 0, 12, 5, 4],
	[0, 0, 0, 13, 5, 4],
	[0, 1, 0, 14, 1, 6, 0, 30, 0, 30, 31, 29, 28, 2, 3],
	[0, 0, 0, 15, 5, 3],
	[0, 0, 0, 16, 5, 3],
	[0, 0, 0, 17, 5, 3],
	[0, 1, 0, 18, 1, 6, 0, 30, 0, 30, 31, 29, 28, 2, 3],
	[0, 0, 0, 19, 5, 3],
	[0, 0, 0, 20, 5, 3],
	[0, 0, 0, 21, 5, 3],
	[0, 0, 0, 22, 5, 3],
	[0, 0, 0, 23, 4],
	[0, 0, 0, 24, 5, 3],
	[0, 0, 0, 25, 5, 3],
	[0, 0, 0, 26, 5, 3],
	[0, 0, 0, 27, 5, 3],
	[0, 0, 0, 28, 5, 3],
	[0, 0, 0, 29, 5, 3],
	[0, 0, 0, 30, 5, 3],
	[0, 0, 0, 31, 5, 3],
	[0, 0, 0, 32, 5, 3],
	[0, 0, 0, 33, 5, 4],
	[0, 1, 0, 15, 4],
]

## Returns a detached source command program for the named animation ID.
static func program(animation_id: int) -> PackedInt32Array:
	return PackedInt32Array(PROGRAMS[animation_id])
