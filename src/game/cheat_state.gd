class_name CheatState
extends RefCounted
## Retail cheat switches that change gameplay rules for one game; both default off.

## Retail Cheat_infinite_lives_toggle (MAIN.C:92), a process global never reset: FrogKill
## (FROG.C:3157-3163) skips the lives decrement and the HUD lives rebuild while it is set,
## but still clears FROG_ACTIVE when fr_lives is zero (FROG.C:3165-3166).
var infinite_lives: bool = false
## Retail PC Cheat_no_death_on_timeout (exe ds:0x478690, toggled by 0x00430040): the PC
## GameCheckStatus skips the whole timeout block (gamesys.C:1822-1879), so the frog keeps
## control and survives a timeout.
var no_death_on_timeout: bool = false

## Returns a detached copy of both switches.
func copy() -> CheatState:
	var result := CheatState.new()
	result.infinite_lives = infinite_lives
	result.no_death_on_timeout = no_death_on_timeout
	return result
