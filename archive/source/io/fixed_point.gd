class_name FixedPoint
extends RefCounted
## Integer width and fixed-point helpers for values taken from the original game.
##
## GDScript integers are 64-bit, but the game did its arithmetic in 16- and
## 32-bit registers. These helpers wrap a 64-bit result back to the width the
## original code stored, so overflow behaves as it did in 1997.
##
## Two fixed-point formats appear throughout the data:
## [br]- [b]4.12[/b]: rotation matrices and some scales; [code]0x1000[/code] is 1.0.
## [br]- [b]16.16[/b]: positions and velocities; [code]0x10000[/code] is 1.0.

## 1.0 in 4.12 fixed point.
const ONE_4_12: int = 0x1000
## 1.0 in 16.16 fixed point.
const ONE_16_16: int = 0x10000


## Wraps [param value] to a signed 16-bit integer (-32768 .. 32767).
static func to_s16(value: int) -> int:
	var v: int = value & 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v


## Wraps [param value] to an unsigned 16-bit integer (0 .. 65535).
static func to_u16(value: int) -> int:
	return value & 0xFFFF


## Wraps [param value] to a signed 32-bit integer.
static func to_s32(value: int) -> int:
	var v: int = value & 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v


## Wraps [param value] to an unsigned 32-bit integer.
static func to_u32(value: int) -> int:
	return value & 0xFFFFFFFF


## Wraps [param value] to a signed 8-bit integer.
static func to_s8(value: int) -> int:
	var v: int = value & 0xFF
	return v - 0x100 if v >= 0x80 else v


## Converts a 4.12 fixed-point integer to a float.
static func from_4_12(value: int) -> float:
	return float(value) / float(ONE_4_12)


## Converts a float to 4.12 fixed point, rounding to nearest.
static func to_4_12(value: float) -> int:
	return roundi(value * float(ONE_4_12))


## Converts a 16.16 fixed-point integer to a float.
static func from_16_16(value: int) -> float:
	return float(value) / float(ONE_16_16)


## Converts a float to 16.16 fixed point, rounding to nearest.
static func to_16_16(value: float) -> int:
	return roundi(value * float(ONE_16_16))


## Multiplies two 4.12 values the way the game's integer code does: a full
## product shifted right by 12 (arithmetic shift, so negatives round down).
static func mul_4_12(a: int, b: int) -> int:
	return (a * b) >> 12
