class_name LevelSelectTable
extends Resource
## The level-select stacks: the arcade list followed directly by the race list.
##
## Each list ends with a row whose level is -1 (FrogLord's [code]readLevelData[/code]).
## [member arcade] and [member race] hold the real rows; the ending rows are
## kept apart in [member arcade_terminator] and [member race_terminator]
## (FrogLord keeps them in its lists).

## Arcade-mode levels in stack order.
@export var arcade: Array[LevelSelectEntry] = []
## Race-mode (multiplayer) levels in stack order.
@export var race: Array[LevelSelectEntry] = []
## The row ending the arcade list.
@export var arcade_terminator: LevelSelectEntry
## The row ending the race list.
@export var race_terminator: LevelSelectEntry
## Why reading failed, or "".
@export var error: String = ""


## The arcade entry for level [param level], else the race entry, else null.
func entry_for_level(level: int) -> LevelSelectEntry:
	for e: LevelSelectEntry in arcade:
		if e.level == level:
			return e
	for e: LevelSelectEntry in race:
		if e.level == level:
			return e
	return null
