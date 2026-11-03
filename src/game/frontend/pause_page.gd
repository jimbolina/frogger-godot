class_name PausePage
extends RefCounted
## The 30 Hz in-game pause (GamePause, pause.c:163-527) from the press to the resume or quit.
##
## [method create] is the press tick (PAUSE_MODE_NO_PAUSE, pause.c:170-200) and each
## [method tick] runs one arm of the pause. INIT shows the PAUSED, CONTINUE and QUIT sprites,
## eight FADE_DOWN ticks darken the screen and lower the sound volume, and MENU reads Escape and
## the menu. Escape, Continue or Quit then No leave through KILL_SPRITES, eight FADE_UP ticks and
## DEINIT, which reports RESUMED; Quit then Yes goes straight to DEINIT, which reports QUIT. The
## game resumes on the tick after DEINIT (gamesys.C:1319 gates logic before :1490 runs the
## pause). [member quit_selection] keeps retail's numbering: [constant QUIT_YES] 0 and
## [constant QUIT_NO] 1 (pause.h:30-35), so Left moves to No and Right to Yes.
##
## Port differences: the frozen C shows Continue and Quit (the hidden menu, pause.c:559-603)
## only after a SELECT release (:300-308), which no retail PC key reaches; retail PC shows them
## as soon as the page opens, and the port does so at INIT, so the PAUSED sprite never glows. Escape stands for FRR_START, as in the retail PC executable
## (0x0042f428). Visibility and glow follow the mode after the tick, so each is one tick early
## against retail: the sprites show from the press tick (retail creates them in the INIT arm) and
## go at KILL_SPRITES (retail kills them in that arm), the glow starts on the tick that enters MENU
## (retail first runs OptionUpdateSpcores on the next MENU tick, pause.c:434) and No glows on the
## tick Quit is chosen (retail still glows Quit, :358). The glow grey comes from the pause's own
## tick count where retail reads the options viewport's frame count (OPTIONS.C:400).
##
## In MENU, when Escape is not pressed and the level is an arcade level, the tick runs
## [member cheats] on the keys down before the hidden menu (pause.c:288-292); each cheat that
## fires adds its CHEAT event, after a CROAK for the three routines that croak.

## Pause_mode values (pause.h).
enum Mode { NO_PAUSE, INIT, FADE_DOWN, MENU, KILL_SPRITES, FADE_UP, DEINIT }
## Pause_hidden_menu_mode while the menu is shown: Continue/Quit, then Yes/No.
enum MenuMode { CONTINUE, QUIT }
## The pause's sprites.
enum Sprite { NONE, PAUSED, CONTINUE, QUIT, YES, NO }
## What a tick asks the game to do: HOP and CROAK play sounds, RESUMED and QUIT end the pause,
## and the CHEAT events apply a fired cheat: a toggle of infinite lives (pause.c:900-915), the
## zone unlock (:933-965), the level unlock (:983-998) and the PC-only toggle of death on timeout
## (exe 0x00430040), which alone does not croak.
enum Event { HOP, CROAK, RESUMED, QUIT, CHEAT_INFINITE_LIVES, CHEAT_ALL_ZONES, CHEAT_ALL_LEVELS, CHEAT_TIMEOUT_DEATHS }

## The fade polygon's colour step per tick (pause.c:240-242, :468-470).
const FADE_STEP: int = 0x10
## The colour that ends the fade-down (pause.c:257).
const FADE_END: int = 0x80
## SFX_GEN_FROG_HOP (sound.h generic bank).
const HOP_SOUND: int = 6
## SFX_GEN_FROG_CROAK (sound.h generic bank).
const CROAK_SOUND: int = 3
## OPTION_TEXT_PAUSED (pause.c:206).
const PAUSED_IMAGE: String = "opt_paused"
## OPTION_TEXT_BIG_CONTINUE (pause.c:561).
const CONTINUE_IMAGE: String = "opt_big_continue"
## OPTION_TEXT_QUIT (pause.c:565).
const QUIT_IMAGE: String = "quit"
## OPTION_TEXT_YES (pause.c:595).
const YES_IMAGE: String = "opt_yes"
## OPTION_TEXT_NO (pause.c:599).
const NO_IMAGE: String = "opt_no"
## Game_display_height >> 1 at the PC's 640x480 display (pause.c:207).
const PAUSED_Y: int = 240
## (Game_display_height >> 1) + 32 (pause.c:562).
const CONTINUE_Y: int = 272
## (Game_display_height >> 1) + 48 (pause.c:566).
const QUIT_Y: int = 288
## (Game_display_height >> 1) + 64 for Yes and No (pause.c:596, :600).
const YES_NO_Y: int = 304
## Yes sits this far right of centre and No this far left (pause.c:596, :600).
const YES_NO_OFFSET: int = 48
## Game_display_width >> 1 at the PC's 640x480 display.
const CENTRE_X: int = 320
## HIDDEN_MENU_CONTINUE_SELECTED (pause.h:41).
const CONTINUE_SELECTED: int = 0
## HIDDEN_MENU_QUIT_SELECTED (pause.h:42).
const QUIT_SELECTED: int = 1
## HIDDEN_MENU_QUIT_YES (pause.h:32).
const QUIT_YES: int = 0
## HIDDEN_MENU_QUIT_NO, the Yes/No menu's first choice (pause.h:33, pause.c:602).
const QUIT_NO: int = 1


## One tick's keys for the pause.
class Buttons:
	extends RefCounted
	## Escape pressed this tick (FRR_START).
	var escape: bool = false
	## Up pressed this tick.
	var up: bool = false
	## Down pressed this tick.
	var down: bool = false
	## Left pressed this tick.
	var left: bool = false
	## Right pressed this tick.
	var right: bool = false
	## Fire released this tick (FRR_CROSS released).
	var fire_released: bool = false
	## The DirectInput scancodes held or pressed this tick, for the cheat sequences.
	var keys_down: PackedInt32Array = PackedInt32Array()
	## True on an arcade level (Sel_mode SEL_MODE_ARCADE), where the cheats are checked.
	var arcade: bool = true


## Pause_mode.
var mode: Mode = Mode.NO_PAUSE
## Pause_hidden_menu_mode.
var menu_mode: MenuMode = MenuMode.CONTINUE
## The fade polygon's colour, 0 to [constant FADE_END].
var fade_level: int = 0
## Pause_volume, the sound-effect volume during the pause.
var volume: int = 0
## Sound_volume, the volume the fade-up returns to.
var sound_volume: int = 0
## Pause_hidden_selection: [constant CONTINUE_SELECTED] or [constant QUIT_SELECTED].
var selection: int = CONTINUE_SELECTED
## Pause_hidden_quit_selection: [constant QUIT_YES] or [constant QUIT_NO].
var quit_selection: int = QUIT_NO
## Ticks run since the press.
var frame: int = 0
## True once Yes was chosen (Game_paused_selection HIDDEN_MENU_QUIT_SELECTED, pause.c:400).
var quitting: bool = false
## The cheat dispatcher the MENU arm runs (pause.c:291), shared across pauses; null checks nothing.
var cheats: PauseCheats = null


## True when the pause may start this tick: the start timer is 0, the frog is active and the
## level is neither complete, starting nor under the game-over page (Game_start_timer and
## GAME_FLAG_NO_PAUSE_ALLOWED, FROG_ACTIVE, pause.c:166-177).
static func allowed(state: GameplayState) -> bool:
	return (state.frog.start_timer == 0 and (state.frog.flags & FrogFlags.ACTIVE) != 0
		and not state.completed
		and state.flow.phase not in [LevelFlowState.Phase.START, LevelFlowState.Phase.GAME_OVER])


## The press tick (pause.c:183-193) with the game's [param game_sound_volume]: the next tick is
## INIT.
static func create(game_sound_volume: int) -> PausePage:
	var page := PausePage.new()
	page.mode = Mode.INIT
	page.sound_volume = game_sound_volume
	page.volume = game_sound_volume
	page.fade_level = 0
	return page


## The press tick's sound (pause.c:193).
func startup_events() -> Array[Event]:
	return [Event.HOP]


## Runs the current mode's arm for one tick with [param buttons] and returns that tick's events.
func tick(buttons: Buttons) -> Array[Event]:
	var events: Array[Event] = []
	if mode == Mode.NO_PAUSE:
		return events
	frame += 1
	match mode:
		Mode.INIT:
			_init_arm()
		Mode.FADE_DOWN:
			_fade_down()
		Mode.MENU:
			_menu(buttons, events)
		Mode.KILL_SPRITES:
			mode = Mode.FADE_UP
		Mode.FADE_UP:
			_fade_up()
		Mode.DEINIT:
			events.append(Event.QUIT if quitting else Event.RESUMED)
			mode = Mode.NO_PAUSE
	return events


## True until the DEINIT tick has run.
func active() -> bool:
	return mode != Mode.NO_PAUSE


## True while the PAUSED, CONTINUE and QUIT sprites are shown.
func shows_sprites() -> bool:
	return mode in [Mode.INIT, Mode.FADE_DOWN, Mode.MENU]


## True while the YES and NO sprites are shown.
func shows_quit() -> bool:
	return shows_sprites() and menu_mode == MenuMode.QUIT


## The sprite that glows: only in MENU, where OptionUpdateSpcores runs (pause.c:434), the
## selected menu item (Option_spcore_index, :358, :427).
func glowing_sprite() -> Sprite:
	if mode != Mode.MENU:
		return Sprite.NONE
	if menu_mode == MenuMode.QUIT:
		return Sprite.YES if quit_selection == QUIT_YES else Sprite.NO
	return Sprite.CONTINUE if selection == CONTINUE_SELECTED else Sprite.QUIT


## The glowing sprite's grey at [param tick_count] ((frame_count & 7) << 5, OPTIONS.C:400).
static func glow(tick_count: int) -> int:
	return (tick_count & 7) << 5


## The left edge of [param sprite] of [param width] pixels, centred on the display with Yes
## [constant YES_NO_OFFSET] right and No left (pause.c:207, :562, :566, :596, :600).
static func sprite_x(width: int, sprite: Sprite) -> int:
	var x: int = CENTRE_X - (width >> 1)
	if sprite == Sprite.YES:
		return x + YES_NO_OFFSET
	if sprite == Sprite.NO:
		return x - YES_NO_OFFSET
	return x


## The top edge of [param sprite], 0 for NONE.
static func sprite_y(sprite: Sprite) -> int:
	match sprite:
		Sprite.PAUSED:
			return PAUSED_Y
		Sprite.CONTINUE:
			return CONTINUE_Y
		Sprite.QUIT:
			return QUIT_Y
		Sprite.YES, Sprite.NO:
			return YES_NO_Y
	return 0


func _init_arm() -> void:
	menu_mode = MenuMode.CONTINUE
	selection = CONTINUE_SELECTED
	quit_selection = QUIT_NO
	volume = sound_volume
	mode = Mode.FADE_DOWN


func _fade_down() -> void:
	fade_level += FADE_STEP
	volume = 0 if volume < 1 else volume - 1
	if fade_level == FADE_END:
		mode = Mode.MENU


func _fade_up() -> void:
	fade_level -= FADE_STEP
	volume = sound_volume if volume >= sound_volume else volume + 1
	if fade_level == 0:
		mode = Mode.DEINIT


func _menu(buttons: Buttons, events: Array[Event]) -> void:
	if buttons.escape:
		mode = Mode.KILL_SPRITES
		events.append(Event.HOP)
		return
	if buttons.arcade and cheats != null:
		_cheat_events(cheats.check(buttons.keys_down), events)
	if menu_mode == MenuMode.CONTINUE:
		_continue_menu(buttons, events)
	else:
		_quit_menu(buttons, events)


func _cheat_events(fired: Array[int], events: Array[Event]) -> void:
	for cheat: int in fired:
		match cheat:
			PauseCheats.Cheat.INFINITE_LIVES:
				events.append(Event.CROAK)
				events.append(Event.CHEAT_INFINITE_LIVES)
			PauseCheats.Cheat.ALL_ZONES:
				events.append(Event.CROAK)
				events.append(Event.CHEAT_ALL_ZONES)
			PauseCheats.Cheat.ALL_LEVELS:
				events.append(Event.CROAK)
				events.append(Event.CHEAT_ALL_LEVELS)
			PauseCheats.Cheat.TIMEOUT_DEATHS:
				events.append(Event.CHEAT_TIMEOUT_DEATHS)


func _continue_menu(buttons: Buttons, events: Array[Event]) -> void:
	if buttons.down and selection < QUIT_SELECTED:
		selection += 1
		events.append(Event.HOP)
	if buttons.up and selection > CONTINUE_SELECTED:
		selection -= 1
		events.append(Event.HOP)
	if not buttons.fire_released:
		return
	events.append(Event.CROAK)
	if selection == CONTINUE_SELECTED:
		mode = Mode.KILL_SPRITES
	else:
		menu_mode = MenuMode.QUIT
		quit_selection = QUIT_NO


func _quit_menu(buttons: Buttons, events: Array[Event]) -> void:
	if buttons.left and quit_selection < QUIT_NO:
		quit_selection += 1
		events.append(Event.HOP)
	if buttons.right and quit_selection > QUIT_YES:
		quit_selection -= 1
		events.append(Event.HOP)
	if not buttons.fire_released:
		return
	events.append(Event.CROAK)
	if quit_selection == QUIT_NO:
		mode = Mode.KILL_SPRITES
	else:
		quitting = true
		mode = Mode.DEINIT
