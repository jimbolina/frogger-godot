class_name ScorePopupState
extends RefCounted
## One rising score sprite of CreateScoreSprite and UpdateScoreSprites (score.C:107-226).
##
## AddFrogScore projects the owner's origin once and creates the sprite there
## with grey 0x80 and timer SCORE_SPRITE_LIFETIME. Each [method update]
## decrements the timer and removes the sprite at zero; otherwise it adds
## -0x8000 to the 16.16 Y, fades up for the first three updates and then
## fades down in proportion to the remaining time.

const LIFETIME: int = 45
const VELOCITY_Y: int = -0x8000
const BASE_GREY: int = 0x80
const FADE_UP_UPDATES: int = 4
const FADE_UP_STEP: int = 0x20

## Score_library slot whose image the sprite shows.
var slot: int = -1
var x: int = 0
var y_16: int = 0
var timer: int = LIFETIME
var grey: int = BASE_GREY
var killed: bool = false


func _init(score_slot: int = -1, at: Vector2i = Vector2i.ZERO) -> void:
	slot = score_slot
	x = at.x
	y_16 = PlatformMath.s32(at.y << 16)


## Runs one UpdateScoreSprites step.
func update() -> void:
	if killed:
		return
	timer -= 1
	if timer == 0:
		killed = true
		return
	y_16 = PlatformMath.s32(y_16 + VELOCITY_Y)
	var age: int = LIFETIME - timer
	grey = age * FADE_UP_STEP if age < FADE_UP_UPDATES else PlatformMath.divide(BASE_GREY * timer, LIFETIME)


## The sprite centre in screen pixels.
func screen() -> Vector2i:
	return Vector2i(x, y_16 >> 16)
