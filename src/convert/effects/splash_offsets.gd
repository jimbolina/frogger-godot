class_name SplashOffsets
extends RefCounted
## Where ENTSCR_CREATE_3D_SPRITE places its splash ripples (scripter.c:1411-1453).
##
## On the original theme the command reads the entity's form id: forms 19, 20
## and 21 are the three turtle forms, and form [code]f[/code] creates
## [code]f − 18[/code] ripples, the first at (0, −0x40, −(f − 19)·128) and each
## next 0x100 further along local Z. Form 18 creates none; below 18 the
## unsigned count wraps, which the source never meant ([method source_defined]
## is false and no ripples are given). Every other theme creates one ripple at
## the entity's frame origin. Offsets are in the entity's frame. Each ripple
## is a 3D sprite in the local XZ plane at ordering offset −0x10 running
## TurtleSplashAnimList.

## THEME_ORG, the original theme's number (FroggerIds.THEMES).
const ORIGINAL_THEME: int = 5
## Form whose ripple count is zero.
const NO_RIPPLE_FORM: int = 18
## Form whose first ripple sits at the frame's Z origin.
const CENTRED_FORM: int = 19
## Local Z spacing of the first ripple's offset per form above [constant CENTRED_FORM].
const LEAD_STEP: int = 128
## Local Z spacing between ripples.
const RIPPLE_STEP: int = 0x100
## Local Y of original-theme ripples.
const RIPPLE_Y: int = -0x40
## The sprites lie in the local XZ plane.
const IN_XZ_PLANE: bool = true
## Source sc_ot_offset of the ripples.
const OT_OFFSET: int = -0x10


## Whether [param theme] and [param form_id] give a count the source meant.
static func source_defined(theme: int, form_id: int) -> bool:
	return theme != ORIGINAL_THEME or form_id >= NO_RIPPLE_FORM


## The ripple offsets in the entity's frame, in creation order.
static func offsets(theme: int, form_id: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if theme != ORIGINAL_THEME:
		result.append(Vector3i.ZERO)
		return result
	if not source_defined(theme, form_id):
		return result
	var at := Vector3i(0, RIPPLE_Y, -(form_id - CENTRED_FORM) * LEAD_STEP)
	for _ripple: int in form_id - NO_RIPPLE_FORM:
		result.append(at)
		at.z += RIPPLE_STEP
	return result
