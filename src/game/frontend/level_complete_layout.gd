class_name LevelCompleteLayout
extends RefCounted
## Where LevelCompleteStartup places each sprite on the 640x480 display (top-left corners,
## tempopt.c:5806-5960), and which sprites [LevelCompletePage] shows this update.
##
## Checkpoint times show their last two digits, the total its last three and the score its last
## six (HUDGetDigits, HUD.C:2522). Checkpoint icons animate at speed 2 (Animlist_hud_checkpoint,
## HUD.C:641-660) and the gold frog at speed 1 (Animlist_level_complete_golden_frog,
## tempopt.c:668). Prompt text is centred on its image width.

## One sprite: an image name and its top-left corner.
class Sprite:
	extends RefCounted
	## Image name.
	var image: String = ""
	## Top-left corner on the 640x480 display.
	var at: Vector2i = Vector2i.ZERO

	## A sprite of [param image_name] at [param corner].
	static func create(image_name: String, corner: Vector2i) -> Sprite:
		var sprite := Sprite.new()
		sprite.image = image_name
		sprite.at = corner
		return sprite


## Stands for the next level's in-game name image (li_level_name_texture_in_game).
const LEVEL_NAME_IMAGE: String = "level_name"
const SECONDS_IMAGE: String = "opt_sec"
const DIGIT_PREFIX: String = "med_"
const CENTRE_X: int = 320
const CHECKPOINT_X: int = 215
const FIRST_ROW_Y: int = 170
const ROW_STEP: int = 20
const TIME_DIGIT_X: PackedInt32Array = [236, 252]
const TIME_SECONDS_X: int = 268
const TOTAL_TIME_LABEL := Vector2i(304, 180)
const TOTAL_TIME_DIGIT_X: PackedInt32Array = [330, 346, 362]
const TOTAL_TIME_Y: int = 200
const TOTAL_TIME_SECONDS := Vector2i(378, 200)
const TOTAL_SCORE_LABEL := Vector2i(298, 225)
const SCORE_DIGIT_X: PackedInt32Array = [310, 326, 342, 358, 374, 390]
const SCORE_Y: int = 245
const GOLD_FROG := Vector2i(215, 270)
const NEXT_Y: int = 390
const LEVEL_NAME_Y: int = 410
const PRESS_FIRE_Y: int = 430
const SELECT_LEVEL_Y: int = 450
const ZONE_COMPLETE_Y: int = 430
const ZONE_PRESS_FIRE_Y: int = 448
const CHECKPOINT_CELS: int = 7
const CHECKPOINT_SPEED: int = 2


## The left edge that centres an image [param width] wide (te_w >> 1, tempopt.c:5912).
static func centred_x(width: int) -> int:
	return CENTRE_X - (width >> 1)


## The last [param count] decimal digits of [param value], zero padded (HUDGetDigits, HUD.C:2522);
## a negative value shows as 0.
static func digits(value: int, count: int) -> String:
	var remaining: int = maxi(value, 0)
	var text: String = ""
	for _digit: int in count:
		text = str(remaining % 10) + text
		remaining = PlatformMath.divide(remaining, 10)
	return text


## The cel of [param checkpoint]'s icon after [param frame] updates (speed 2, HUD.C:641-660).
static func checkpoint_image(checkpoint: int, frame: int) -> String:
	return "babyfrog%d_%d" % [checkpoint + 1, PlatformMath.divide(frame, CHECKPOINT_SPEED) % CHECKPOINT_CELS]


## The gold frog's cel after [param frame] updates (speed 1, tempopt.c:668).
static func gold_image(frame: int) -> String:
	return "babyfroggold_%d" % (frame % CHECKPOINT_CELS)


## The sprites [param page] shows now, in LevelCompleteStartup's order; centred text uses
## [param widths] by image name (0 when missing).
static func sprites(page: LevelCompletePage, widths: Dictionary[String, int]) -> Array[Sprite]:
	var result: Array[Sprite] = []
	for index: int in LevelCompletePage.CHECKPOINT_COUNT:
		var y: int = FIRST_ROW_Y + ROW_STEP * index
		var seconds: int = page.checkpoint_seconds[index] if index < page.checkpoint_seconds.size() else 0
		result.append(Sprite.create(checkpoint_image(index, page.frame), Vector2i(CHECKPOINT_X, y)))
		_append_digits(result, seconds, TIME_DIGIT_X, y)
		result.append(Sprite.create(SECONDS_IMAGE, Vector2i(TIME_SECONDS_X, y)))
	result.append(Sprite.create("total_time", TOTAL_TIME_LABEL))
	_append_digits(result, page.total_seconds, TOTAL_TIME_DIGIT_X, TOTAL_TIME_Y)
	result.append(Sprite.create(SECONDS_IMAGE, TOTAL_TIME_SECONDS))
	result.append(Sprite.create("total_score", TOTAL_SCORE_LABEL))
	_append_digits(result, page.level_score, SCORE_DIGIT_X, SCORE_Y)
	if page.show_gold_frog:
		result.append(Sprite.create(gold_image(page.frame), GOLD_FROG))
	if page.variant == LevelCompletePage.Kind.NEXT_LEVEL:
		_append_centred(result, "next", NEXT_Y, widths)
		_append_centred(result, LEVEL_NAME_IMAGE, LEVEL_NAME_Y, widths)
		if page.press_fire_visible:
			_append_centred(result, "press_fire", PRESS_FIRE_Y, widths)
		_append_centred(result, "select4", SELECT_LEVEL_Y, widths)
	elif page.variant == LevelCompletePage.Kind.ZONE_COMPLETE:
		_append_centred(result, "zone_complete", ZONE_COMPLETE_Y, widths)
		if page.press_fire_visible:
			_append_centred(result, "press_fire", ZONE_PRESS_FIRE_Y, widths)
	return result


static func _append_digits(result: Array[Sprite], value: int, xs: PackedInt32Array, y: int) -> void:
	var text: String = digits(value, xs.size())
	for index: int in xs.size():
		result.append(Sprite.create(DIGIT_PREFIX + text[index], Vector2i(xs[index], y)))


static func _append_centred(result: Array[Sprite], image_name: String, y: int, widths: Dictionary[String, int]) -> void:
	var width: int = widths.get(image_name, 0)
	result.append(Sprite.create(image_name, Vector2i(centred_x(width), y)))
