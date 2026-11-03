class_name GameOverPage
extends RefCounted
## The 30 Hz game-over page of retail PC (GameOverStartup, GameOverUpdate, tempopt.c:4057-4175,
## tempopt.h:43-44; compiled GameOverStartup 0x00443630 and GameOverUpdate 0x00443700 in
## FROGGER.EXE).
##
## Startup sets [member units] to GAME_OVER_DURATION + GAME_OVER_PREDELAY (165), plays disc track
## 22 once (StopCD, PlayCD(22, 0)), sets the effects volume to 0 so every effect, the croak
## included, is silent, hides the HUD viewport (MR_VP_NO_DISPLAY) and prepares the shrink helper
## 0x00435490 with 165 >> 2 steps of 480 / 41 pixels. Each update lowers [member units]; for the
## first 30 updates nothing else happens. Then [member units] reaching 0 or fire below
## [constant FIRE_UNITS] (from update 76, with a croak request) leaves for CONTINUE, and on every
## update the shrink helper 0x004354e0 narrows the game viewport about the centre of the 640x480
## display and the opt_gameover sprite's grey rises over [constant FADE_TICKS] updates to 0x7F.
## The level keeps updating under the page (tempopt.c:4112). The port's sprite fade follows
## retail's hardware-capability path (display-capability bit 0), the one that colours the sprite.
## Once an exit is chosen further ticks change nothing.

## GAME_OVER_DURATION (tempopt.h:43).
const DURATION: int = 105
## GAME_OVER_PREDELAY (tempopt.h:44).
const PREDELAY: int = 60
## Updates over which the sprite grey rises.
const FADE_TICKS: int = 30
## Fire is read once [member units] falls below this.
const FIRE_UNITS: int = DURATION - 15
## SFX_GEN_FROG_CROAK.
const SOUND_CROAK: int = 3
## The disc track PlayCD(22, 0) starts once, the PC game-over jingle.
const JINGLE_TRACK: int = 22
const DISPLAY_WIDTH: int = 640
const DISPLAY_HEIGHT: int = 480
## The sprite texture's name.
const IMAGE: String = "opt_gameover"

## Options_count_down_units.
var units: int = DURATION + PREDELAY
## Completed updates.
var frame: int = 0
## Steps of the shrink, the startup [member units] >> 2.
var shrink_steps: int = (DURATION + PREDELAY) >> 2
## Pixels the viewport width loses per update.
var width_step: int = DISPLAY_HEIGHT / ((DURATION + PREDELAY) >> 2)
## Width of the game viewport in display pixels.
var view_width: int = DISPLAY_WIDTH
## Height of the game viewport in display pixels.
var view_height: int = DISPLAY_HEIGHT
## Grey of the opt_gameover sprite, 0 to 0x7F.
var sprite_grey: int = 0
## True when the pause menu's Quit opened the page.
var quit: bool = false
## Sound ids requested by the latest tick.
var sounds: PackedInt32Array = PackedInt32Array()
## The [enum FrontEndFlow.Event] chosen, or -1 while the page is open.
var exit_event: int = -1


## The page at startup, opened by the pause menu's Quit when [param from_quit].
static func create(from_quit: bool) -> GameOverPage:
	var page := GameOverPage.new()
	page.quit = from_quit
	page.units = DURATION + PREDELAY
	page.shrink_steps = page.units >> 2
	page.width_step = DISPLAY_HEIGHT / page.shrink_steps
	return page


## The disc track the startup plays once.
func startup_track() -> int:
	return JINGLE_TRACK


## True: the startup sets the effects volume to 0 for the whole page.
func mutes_effects() -> bool:
	return true


## True: the startup hides the HUD viewport.
func hides_hud() -> bool:
	return true


## True once [member units] is below [constant FIRE_UNITS] and the page is open. [method tick]
## reads fire after its decrement, so the update that takes [member units] from 90 to 89 reads it
## too.
func accepts_fire() -> bool:
	return units < FIRE_UNITS and not finished()


## True once an exit is chosen.
func finished() -> bool:
	return exit_event >= 0


## True once the predelay is over and the shrink and sprite are live.
func overlay_visible() -> bool:
	return units < DURATION + 30


## The game viewport centred on the 640x480 display.
func view_rect() -> Rect2i:
	return Rect2i((DISPLAY_WIDTH - view_width) >> 1, (DISPLAY_HEIGHT - view_height) >> 1, view_width, view_height)


## Advances one update with [param fire] pressed in retail's order and returns
## [member exit_event]. Nothing changes once finished.
func tick(fire: bool) -> int:
	if finished():
		return exit_event
	frame += 1
	sounds = PackedInt32Array()
	units -= 1
	if units < DURATION + 30:
		if units == 0:
			exit_event = FrontEndFlow.Event.GAME_OVER_DONE
		elif units < FIRE_UNITS and fire:
			sounds.append(SOUND_CROAK)
			exit_event = FrontEndFlow.Event.GAME_OVER_DONE
		view_width = maxi(0, view_width - width_step)
		view_height = DISPLAY_HEIGHT * view_width / DISPLAY_WIDTH
		sprite_grey = mini(255, (DURATION + 30 - units) * 255 / FADE_TICKS) >> 1
	return exit_event
