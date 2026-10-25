extends GutTest
## FixedPoint: wrapping 64-bit results to the game's widths, and fixed-point conversions.


func test_s16_wraps_like_a_16_bit_register() -> void:
	assert_eq(FixedPoint.to_s16(0x7FFF), 32767)
	assert_eq(FixedPoint.to_s16(0x8000), -32768)
	assert_eq(FixedPoint.to_s16(0xFFFF), -1)
	assert_eq(FixedPoint.to_s16(0x12345), 0x2345)
	assert_eq(FixedPoint.to_s16(-32769), 32767)
	assert_eq(FixedPoint.to_u16(-1), 0xFFFF)


func test_s32_wraps_like_a_32_bit_register() -> void:
	assert_eq(FixedPoint.to_s32(0x7FFFFFFF + 1), -2147483648)
	assert_eq(FixedPoint.to_s32(0xFFFFFFFF), -1)
	assert_eq(FixedPoint.to_s32(-2147483649), 2147483647)
	assert_eq(FixedPoint.to_u32(-1), 0xFFFFFFFF)
	assert_eq(FixedPoint.to_s8(0x80), -128)


func test_the_game_rng_step_wraps_to_32_bits() -> void:
	var s: int = 0
	var outputs: Array[int] = []
	for _i: int in 3:
		s = FixedPoint.to_u32(s * 0x41C64E6D + 0x3039)
		outputs.append((s >> 16) & 0x7FFF)
	assert_eq(outputs, [0, 21468, 9988] as Array[int])


func test_4_12_conversions() -> void:
	assert_eq(FixedPoint.from_4_12(0x1000), 1.0)
	assert_eq(FixedPoint.from_4_12(-0x800), -0.5)
	assert_eq(FixedPoint.to_4_12(0.25), 0x400)
	assert_eq(FixedPoint.mul_4_12(0x2000, 0x800), 0x1000)
	assert_eq(FixedPoint.mul_4_12(-1, 1), -1, "arithmetic shift rounds toward minus infinity")


func test_16_16_conversions() -> void:
	assert_eq(FixedPoint.from_16_16(0x18000), 1.5)
	assert_eq(FixedPoint.to_16_16(-2.0), -0x20000)
