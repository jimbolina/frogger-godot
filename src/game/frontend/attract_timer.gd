class_name AttractTimer
extends RefCounted
## The main menu's HIGH_SCORE_VIEW dwell and the demo phases at 30 Hz (tempopt.c MainOptionsUpdate).
##
## One method call is one MainOptionsUpdate call. HIGH_SCORE_VIEW_INIT falls through into
## VIEW_MAIN (tempopt.c:1650), so the caller follows [method start_dwell] with [method dwell_tick]
## in the same tick; 819 more VIEW_MAIN calls then end the dwell (SCORE_TIME plus the nine calls
## the fly-on holds the exit closed). The port folds the C's bookkeeping calls into its
## transitions: VIEW_FINISH and DEMO_LOADING_INIT into the dwell's exit, and GAME_START and
## LEVEL_START into [method start_demo]. The port loads a demo synchronously, so LOADING lasts
## exactly the menu's fly-off.

enum Phase { DWELL, LOADING, PLAYING, FADE_OUT, FINISHED }

## SCORE_TIME under PSX_RELEASE, which the PC build defines (tempopt.h:25-29, PC/winsys.h:29).
const SCORE_TIME: int = 810
## OPTIONS_CAMERA_FLYON_TIME and OPTIONS_CAMERA_FLYOFF_TIME (tempopt.h:314-316).
const FLY_TIME: int = 10
## Options_count_down_units of the fade-out (tempopt.c:1502).
const FADE_UNITS: int = 30
## The Demo_time that ends a demo (tempopt.c:1496).
const DEMO_END_TICKS: int = 30
## LOADING sprite colour step per fly-off call (tempopt.c:1413-1415, :1530-1532).
const LOADING_BRIGHTEN: int = 16
## Menu sprite step per fly call (tempopt.c:1410-1412, :1486-1488).
const MENU_SLIDE: int = 8

var phase: int = Phase.DWELL
## The dwell's static score_time count-down.
var score_time: int = 0
## High_score_view_flyon_counter for the menu sprites.
var fly_on: int = 0
## High_score_view_flyoff_counter.
var fly_off: int = 0
## 0..255 LOADING sprite colour.
var loading_brightness: int = 0
## 0..255 grey of the subtractive fade poly.
var fade_grey: int = 0
## Options_count_down_units of the fade-out.
var count_down_units: int = 0


## HIGH_SCORE_VIEW_INIT (tempopt.c:1629-1650, HSView.c:2492): the dwell starts with the menu
## flying on. [param immediate] sets score_time 0 so the demo starts once the fly-on ends.
func start_dwell(immediate: bool = false) -> void:
	phase = Phase.DWELL
	score_time = 0 if immediate else SCORE_TIME
	fly_on = FLY_TIME
	fly_off = 0
	loading_brightness = 0
	fade_grey = 0
	count_down_units = 0


## One HIGH_SCORE_VIEW_MAIN call (tempopt.c:1653-1685): the fly counters fall as HSUpdateFlying
## does (HSView.c:2983-2993); with both at zero and no [param delayed] request, score_time counts
## down and the call that finds it 0 ends the dwell (the C's post-decrement; the port does not
## wrap). The exit enters LOADING with the menu flying off and the LOADING sprite black.
func dwell_tick(delayed: bool) -> int:
	if phase != Phase.DWELL:
		return phase
	if fly_on > 0:
		fly_on -= 1
	if fly_off > 0:
		fly_off -= 1
	if fly_off == 0 and fly_on == 0 and not delayed:
		if score_time == 0:
			phase = Phase.LOADING
			fly_off = FLY_TIME
			fly_on = 0
			loading_brightness = 0
		else:
			score_time -= 1
	return phase


## One DEMO_LOADING call (tempopt.c:1403-1431): while the fly-off runs the menu slides down and
## the LOADING sprite brightens. The C's `if (flyoff--)` is taken only while the counter is
## positive, as the load completes on the call that reaches 0.
func loading_tick() -> int:
	if phase == Phase.LOADING and fly_off > 0:
		fly_off -= 1
		loading_brightness = mini(255, loading_brightness + LOADING_BRIGHTEN)
	return phase


## True once the fly-off has finished while LOADING; the caller then starts the demo level.
func loading_done() -> bool:
	return phase == Phase.LOADING and fly_off == 0


## DEMO_LOADING_LEVEL_START (tempopt.c:1455-1476): the demo runs and the menu flies back on.
func start_demo() -> void:
	phase = Phase.PLAYING
	fly_on = FLY_TIME
	fly_off = 0


## One DEMO_MAIN call (tempopt.c:1481-1514) after the game tick that left [param demo_time]
## (gamesys.C:1357-1363): the menu slides on, then the demo ends when demo_time is
## [constant DEMO_END_TICKS] or less. The C tests `== 30`, which never fires for a demo shorter
## than 30 frames; the port's `<=` ends it. The fade starts with the menu flying off and the
## LOADING sprite black.
func demo_tick(demo_time: int) -> int:
	if phase != Phase.PLAYING:
		return phase
	if fly_on > 0:
		fly_on -= 1
	if demo_time <= DEMO_END_TICKS:
		phase = Phase.FADE_OUT
		count_down_units = FADE_UNITS
		fly_off = FLY_TIME
		fly_on = 0
		loading_brightness = 0
		fade_grey = 0
	return phase


## One DEMO_FADE_OUT call (tempopt.c:1517-1557): the menu flies off and the LOADING sprite
## brightens, and the fade poly's grey rises to 255 over [constant FADE_UNITS] calls
## (subtractive, so the picture goes black). The last call enters FINISHED.
func fade_tick() -> int:
	if phase != Phase.FADE_OUT:
		return phase
	if fly_off > 0:
		loading_brightness = mini(255, loading_brightness + LOADING_BRIGHTEN)
		fly_off -= 1
	count_down_units -= 1
	fade_grey = mini(255, ((FADE_UNITS - count_down_units) * 255) / FADE_UNITS)
	if count_down_units == 0:
		phase = Phase.FINISHED
	return phase


## The menu sprites' offset in pixels below their rest rows: fly_on steps while flying on,
## the completed fly-off steps while flying off, fully off after the load and the fade. The C's
## dwell places the rows 90 below and moves them nine times, so retail rests 18 lower than the
## port's rows; the golden records the C offset beside this one.
func menu_slide() -> int:
	match phase:
		Phase.LOADING, Phase.FADE_OUT:
			return (FLY_TIME - fly_off) * MENU_SLIDE
		Phase.FINISHED:
			return FLY_TIME * MENU_SLIDE
		Phase.DWELL:
			if fly_off > 0:
				return (FLY_TIME - fly_off) * MENU_SLIDE
	return fly_on * MENU_SLIDE


## The main menu's fire gate (tempopt.c:1811-1817): no fly-on or fly-off, no demo [param loading]
## and no [param delayed] request.
func fire_allowed(loading: bool, delayed: bool) -> bool:
	return fly_on == 0 and fly_off == 0 and not loading and not delayed
