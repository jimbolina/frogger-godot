class_name LevelCompletePage
extends RefCounted
## The 30 Hz level-complete options page (LevelCompleteStartup, LevelCompleteUpdate,
## tempopt.c:5792-6067).
##
## The page shows the level's five checkpoint times, their total, the level score and, when a gold
## frog was found, the gold frog. A countdown of [member units] steps of 31 ticks falls from 20 to
## 17 and then stops, so the page never times out (tempopt.c:5995-6008). NEXT_LEVEL and
## ZONE_COMPLETE show the prompt: fire is read once [member units] is below 19 and skips straight
## to the next page with a croak; BACK leaves at once. STATISTICS shows only the figures and reads
## no keys. The press-fire prompt blinks from the page's own update count where retail uses
## MRFrame_number (tempopt.c:6022). Once an exit is chosen further ticks change nothing.
##
## The music follows retail PC (LevelCompleteStartup 0x00444dc0), not the PSX XA handling of
## tempopt.c:5920-5940: NEXT_LEVEL plays sound 8 and stops the level track (MRSNDPlaySound
## 0x004454d4, then PauseCD 0x004454dc, a plain stop that nothing resumes); ZONE_COMPLETE plays no
## sound and starts the zone's tune once in place of the level track (PlayZoneComplete 0x0043e580,
## called at 0x0044558c: PlayCD(Game_map_theme + 22, 0)). The page's shutdown runs GameEnd
## (0x00445902), whose StopCD silences whatever still plays. STATISTICS leaves the music alone.

## NEXT_LEVEL moves on within the zone, ZONE_COMPLETE ends the zone (Level_complete_next_level
## FALSE in arcade mode) and STATISTICS shows the figures without a prompt.
enum Kind { NEXT_LEVEL, ZONE_COMPLETE, STATISTICS }

const CHECKPOINT_COUNT: int = 5
## Options_count_down_units at startup (tempopt.c:5804).
const START_UNITS: int = 20
## NUM_GAME_OVER_TICKS, which is NUM_OPTION_TICKS (tempopt.h:33, :42).
const UNIT_TICKS: int = 31
## Units only fall while above 17 (tempopt.c:6001).
const LAST_UNITS: int = 17
## Fire is read once units fall below 19 (tempopt.c:6011).
const FIRE_UNITS: int = 19
## Press fire is hidden while this bit of the frame count is set (tempopt.c:6022).
const BLINK_BIT: int = 16
## The MR_ULONG countdown wraps (tempopt.c:64-65).
const COUNTER_MASK: int = 0xFFFFFFFF
## SFX_MUSIC_LEVEL_COMPLETE.
const SOUND_LEVEL_COMPLETE: int = 8
## SFX_GEN_FROG_CROAK.
const SOUND_CROAK: int = 3
## Disc track of theme 0 in PlayZoneComplete's PlayCD(Game_map_theme + 22, 0).
const ZONE_TRACK_BASE: int = 22
## THEME_CAV, the first zone theme (gamesys.H:70-80).
const FIRST_ZONE_THEME: int = 1
## THEME_VOL, the last zone theme.
const LAST_ZONE_THEME: int = 10

## Which [enum Kind] the page shows.
var variant: Kind = Kind.STATISTICS
## The next level's id for NEXT_LEVEL, otherwise -1.
var next_level: int = -1
## Whole seconds of each checkpoint (Frog_time_data, FROG.C:2833-2842).
var checkpoint_seconds: PackedInt32Array = PackedInt32Array()
## The sum of [member checkpoint_seconds] (tempopt.c:5822).
var total_seconds: int = 0
## The level score (Frog_score_data[Game_map][0].he_score, tempopt.c:5837).
var level_score: int = 0
## True when the gold frog is shown (tempopt.c:5901-5936).
var show_gold_frog: bool = false
## Options_count_down_units.
var units: int = START_UNITS
## Options_count_down_ticks, an unsigned 32-bit count.
var ticks: int = UNIT_TICKS
## Completed updates.
var frame: int = 0
## True while the press-fire prompt is shown.
var press_fire_visible: bool = false
## The [enum FrontEndFlow.Event] chosen, or -1 while the page is open.
var exit_event: int = -1
## Sound ids requested by the latest tick.
var sounds: PackedInt32Array = PackedInt32Array()


## A page of [param page_variant] leading to [param next_level_id], with the whole seconds of
## [param checkpoint_ticks] (missing checkpoints count 0), [param score] and the gold frog when
## [param gold_frog].
static func create(page_variant: Kind, next_level_id: int, checkpoint_ticks: PackedInt32Array,
		score: int, gold_frog: bool) -> LevelCompletePage:
	var page := LevelCompletePage.new()
	page.variant = page_variant
	page.next_level = next_level_id
	page.level_score = score
	page.show_gold_frog = gold_frog
	for index: int in CHECKPOINT_COUNT:
		var ticks_at: int = checkpoint_ticks[index] if index < checkpoint_ticks.size() else 0
		var seconds: int = HighScoreBoard.checkpoint_seconds(ticks_at)
		page.checkpoint_seconds.append(seconds)
		page.total_seconds += seconds
	return page


## Sounds started by the page's startup: the level-complete jingle for NEXT_LEVEL only
## (0x004454d4).
func startup_sounds() -> PackedInt32Array:
	if variant == Kind.NEXT_LEVEL:
		return PackedInt32Array([SOUND_LEVEL_COMPLETE])
	return PackedInt32Array()


## True when the page's startup stops the level music, NEXT_LEVEL only (PauseCD 0x004454dc).
func stops_music() -> bool:
	return variant == Kind.NEXT_LEVEL


## The disc track the page's startup plays once for a level of [param theme]: the zone's tune
## for ZONE_COMPLETE, otherwise -1.
func startup_track(theme: int) -> int:
	if variant == Kind.ZONE_COMPLETE:
		return zone_track(theme)
	return -1


## The zone-complete tune of [param theme], 23 for THEME_CAV to 32 for THEME_VOL, or -1 for a
## theme that ends no zone.
static func zone_track(theme: int) -> int:
	if theme < FIRST_ZONE_THEME or theme > LAST_ZONE_THEME:
		return -1
	return theme + ZONE_TRACK_BASE


## True when the page shows the prompt and reads the keys.
func shows_prompt() -> bool:
	return variant != Kind.STATISTICS


## True when fire skips the page now (tempopt.c:6011-6020).
func accepts_fire() -> bool:
	return shows_prompt() and units < FIRE_UNITS


## True once an exit is chosen.
func finished() -> bool:
	return exit_event >= 0


## Advances one update with [param fire] and [param back] pressed (tempopt.c:5996-6067) and
## returns [member exit_event]. BACK is checked after fire, so both in one tick croak and leave
## with BACK. Nothing changes once finished.
func tick(fire: bool, back: bool) -> int:
	if finished():
		return exit_event
	frame += 1
	sounds = PackedInt32Array()
	ticks = (ticks - 1) & COUNTER_MASK
	if ticks == 0 and units > LAST_UNITS:
		units -= 1
		ticks = UNIT_TICKS
	if accepts_fire():
		if fire:
			units = 0
			ticks = 0
			sounds.append(SOUND_CROAK)
		press_fire_visible = (frame & BLINK_BIT) == 0
	if shows_prompt() and back:
		exit_event = FrontEndFlow.Event.BACK
	elif shows_prompt() and units == 0 and ticks == 0:
		exit_event = FrontEndFlow.Event.NEXT_LEVEL if variant == Kind.NEXT_LEVEL else FrontEndFlow.Event.ZONE_COMPLETE
	return exit_event
