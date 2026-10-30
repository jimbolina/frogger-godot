class_name LevelStack
extends RefCounted
## The arcade and race level-select stacks handed in by setup, in the executable's order.
##
## Rows and the stack are read-only after creation; progress keeps any change of a row's
## level (the jungle rewrite) itself.


## One stack row: the identity fields of the game's SEL_LEVEL_INFO.
class Row:
	extends RefCounted
	var _level: int = 0
	var _world: int = 0
	var _stack_position: int = 0
	var _theme: int = 0
	var _local_level: int = 0
	var _levels_in_world: int = 0

	## Level number as shipped.
	var level: int:
		get:
			return _level
	## World number; consecutive rows of one world form a zone.
	var world: int:
		get:
			return _world
	## Block of the stack that holds the row.
	var stack_position: int:
		get:
			return _stack_position
	## Theme number, indexing the gold-frog bits.
	var theme: int:
		get:
			return _theme
	## Position inside the world.
	var local_level: int:
		get:
			return _local_level
	## Number of levels in the world.
	var levels_in_world: int:
		get:
			return _levels_in_world

	func _init(level_number: int = 0, world_number: int = 0, position: int = 0,
			theme_number: int = 0, position_in_world: int = 0, world_size: int = 0) -> void:
		_level = level_number
		_world = world_number
		_stack_position = position
		_theme = theme_number
		_local_level = position_in_world
		_levels_in_world = world_size


var _arcade: Array[Row] = []
var _race: Array[Row] = []


## A stack holding [param arcade_rows] and [param race_rows] in the given order.
static func create(arcade_rows: Array[Row], race_rows: Array[Row]) -> LevelStack:
	var stack := LevelStack.new()
	stack._arcade = arcade_rows.duplicate()
	stack._race = race_rows.duplicate()
	return stack


## Number of arcade rows.
func arcade_count() -> int:
	return _arcade.size()


## Arcade row [param index] in stack order.
func arcade_row(index: int) -> Row:
	return _arcade[index]


## Number of race rows.
func race_count() -> int:
	return _race.size()


## Race row [param index] in stack order.
func race_row(index: int) -> Row:
	return _race[index]


## The first arcade index whose shipped level is [param level], or -1.
func arcade_index_of(level: int) -> int:
	for index: int in _arcade.size():
		if _arcade[index].level == level:
			return index
	return -1


## The first race index whose shipped level is [param level], or -1.
func race_index_of(level: int) -> int:
	for index: int in _race.size():
		if _race[index].level == level:
			return index
	return -1
