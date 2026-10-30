class_name FrogTint
extends RefCounted
## Frozen frog mesh colour inputs: map-edge fade, drowning tint, Volcano char and reset ambient.

## Source MR_INST_USE_CUSTOM_AMBIENT.
const CUSTOM_AMBIENT: int = 1
## Source MR_INST_USE_SCALED_COLOURS.
const SCALED_COLOURS: int = 2
## Source THEME_SWP, whose drowning tint is green sludge instead of blue water.
const THEME_SWAMP: int = 7
## Source fade strength inside the fade rectangle.
const NEUTRAL: int = 0x80
const DROWN_AMBIENT: Vector3i = Vector3i(32, 64, 64)
const UNSIGNED32: int = 0xffffffff

## Source FrogInitCustomAmbient (FROG.C:412-440), run by ResetFrog: a nonzero signed header colour
## enables the custom ambient packed as ((red+0x80)<<16)+((green+0x80)<<8)+(blue+0x80), whose low
## byte lands in the red component; an all-zero header turns both modified-light bits off.
static func reset(frog: FrogState, header: Vector3i) -> void:
	if header == Vector3i.ZERO:
		frog.tint_flags &= ~(CUSTOM_AMBIENT | SCALED_COLOURS)
		return
	var packed: int = (((header.x + 0x80) << 16) + ((header.y + 0x80) << 8) + (header.z + 0x80)) & UNSIGNED32
	frog.custom_ambient = _bytes(packed)
	frog.tint_flags = (frog.tint_flags | CUSTOM_AMBIENT) & ~SCALED_COLOURS

## Source SetFrogScaleColours (FROG.C:3420-3441): one packed colour for both the custom ambient and
## the colour scale, with both modified-light bits set.
static func set_scale_colours(frog: FrogState, colour: Vector3i) -> void:
	var packed: int = ((colour.z << 16) + (colour.y << 8) + colour.x) & UNSIGNED32
	frog.custom_ambient = _bytes(packed)
	frog.colour_scale = _bytes(packed)
	frog.tint_flags |= CUSTOM_AMBIENT | SCALED_COLOURS

## Source UpdateFrogBaseColour (FROG.C:3319-3393), run after collision and effects every tick.
static func update(frog: FrogState, cave_light: bool, fade_bounds: Rect2i, theme: int) -> void:
	var translation := Vector3i(frog.matrix12[9], frog.matrix12[10], frog.matrix12[11])
	if not cave_light:
		var grey: int = edge_fade(translation, fade_bounds)
		frog.colour_scale = Vector3i(grey, grey, grey)
		frog.tint_flags |= SCALED_COLOURS
	if frog.mode == FrogMode.DYING and frog.death_equate == FrogAnimationCatalog.DROWN:
		var scale: Vector3i = drowning_scale(PlatformMath.s32(translation.y - frog.old_y), theme)
		frog.custom_ambient = DROWN_AMBIENT
		frog.colour_scale = Vector3i(scale.x & 255, scale.y & 255, scale.z & 255)
		frog.tint_flags |= CUSTOM_AMBIENT | SCALED_COLOURS

## Source edge fade grey for a translation outside the Fade_top_left_pos/Fade_bottom_right_pos
## rectangle: MAX(0, 0x80 - (x_offset + z_offset) / 2) with unsigned offsets. The rectangle spans
## top-left X to bottom-right X and bottom-right Z to top-left Z.
static func edge_fade(translation: Vector3i, fade_bounds: Rect2i) -> int:
	var x_offset: int = 0
	var z_offset: int = 0
	if translation.x < fade_bounds.position.x:
		x_offset = (fade_bounds.position.x - translation.x) & UNSIGNED32
	elif fade_bounds.end.x < translation.x:
		x_offset = (translation.x - fade_bounds.end.x) & UNSIGNED32
	if translation.z < fade_bounds.position.y:
		z_offset = (fade_bounds.position.y - translation.z) & UNSIGNED32
	elif fade_bounds.end.y < translation.z:
		z_offset = (translation.z - fade_bounds.end.y) & UNSIGNED32
	var strength: int = PlatformMath.s32(((x_offset + z_offset) & UNSIGNED32) >> 1)
	return maxi(0, NEUTRAL - strength)

## Source drowning colour scale before the byte stores, from the signed fall since landing:
## Swamp green sludge, otherwise blue water. Components are not clamped above.
static func drowning_scale(delta_y: int, theme: int) -> Vector3i:
	var shifted4: int = PlatformMath.s32(delta_y << 4)
	var shifted5: int = PlatformMath.s32(delta_y << 5)
	var sinking5: int = PlatformMath.s32(-shifted5) >> 9
	var red: int = maxi(PlatformMath.s32(-shifted4) >> 9, 0)
	if theme == THEME_SWAMP:
		return Vector3i(red, maxi((shifted5 >> 9) + 128, 0), maxi(sinking5 + 32, 0))
	return Vector3i(red, maxi(sinking5 + 64, 0), maxi(sinking5 + 192, 0))

static func _bytes(packed: int) -> Vector3i:
	return Vector3i(packed & 255, (packed >> 8) & 255, (packed >> 16) & 255)
