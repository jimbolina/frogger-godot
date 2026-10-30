class_name GlowPulse
extends RefCounted
## The pulse the pickup and gold-frog glows share (Pickup_move/Pickup_disp and
## Gold_frog_glow_move/Gold_frog_glow_disp, PARTICLE.C:2607-2724).
##
## Each move adds [constant STEP] to a 12-bit angle starting at 0. The display
## magnitude is [code](rsin(angle) + 0x3800) << 3[/code] and the projected half
## size of a [code]w[/code] by [code]h[/code] image is
## [code]((w · magnitude) / otz) >> 8[/code], or [code]>> 9[/code] with more
## than two viewports, stored as a signed short. [code]otz[/code] is the
## ordering entry after the effect's own offset; the source draws only when it
## lies inside the table. Sines use the shared rounded 12-bit table.

## Angle added by each move.
const STEP: int = 0x100
## Mask of the 12-bit angle.
const ANGLE_MASK: int = 0xfff
## Bias added to the sine before the shift.
const BASE: int = 0x3800
## Left shift from the biased sine to the magnitude.
const MAGNITUDE_SHIFT: int = 3
## Viewport count above which the glows are halved.
const SPLIT_VIEWPORTS: int = 2


## The angle after [param moves] moves from 0.
static func angle_after(moves: int) -> int:
	return (maxi(0, moves) * STEP) & ANGLE_MASK


## The angle one move after [param angle].
static func step(angle: int) -> int:
	return (angle + STEP) & ANGLE_MASK


## The rounded 12-bit sine of [param angle].
static func rsin(angle: int) -> int:
	return roundi(sin(float(angle & ANGLE_MASK) * TAU / 4096.0) * 4096.0)


## The 16.16 glow magnitude at [param angle].
static func magnitude(angle: int) -> int:
	return (rsin(angle) + BASE) << MAGNITUDE_SHIFT


## Projected half extents in pixels of a [param width] by [param height] image
## at ordering entry [param otz] and [param angle] with [param viewports]
## viewports; zero when [param otz] is not positive.
static func half_size(width: int, height: int, otz: int, angle: int, viewports: int = 1) -> Vector2i:
	if otz <= 0:
		return Vector2i.ZERO
	var amount: int = magnitude(angle)
	var shift: int = 9 if viewports > SPLIT_VIEWPORTS else 8
	return Vector2i(PlatformMath.s16(PlatformMath.divide(width * amount, otz) >> shift),
		PlatformMath.s16(PlatformMath.divide(height * amount, otz) >> shift))
