class_name LevelSelectEntry
extends Resource
## One level on the level-select stack (the game's [code]SEL_LEVEL_INFO[/code]).
##
## Layout on PC (FrogLord's [code]FroggerLevelSelectEntry[/code]), 92 bytes:
## [codeblock]
## s32 level   s32 world   s32 stack position   s32 theme
## s32 level within world (0-4)   s32 levels in world
## u32 x6 texture record addresses: world image (unlocked), world image
##     (visited, unused), world image (not tried), level screenshot,
##     level name on the stack, level name in game
## 44 bytes the game fills in at run time (zero in the file)
## [/codeblock]
## A level number of -1 ends a list; that row's other fields are not meaningful.

## Size of an entry in bytes.
const SIZE: int = 92
## Bytes at the end of an entry that the game uses at run time.
const RUNTIME_SIZE: int = 44
## Level number of the row that ends a list.
const TERMINATOR_LEVEL: int = -1

## Level number, or [constant TERMINATOR_LEVEL].
@export var level: int = 0
## World number (see [FroggerIds]); levels of one world are grouped together.
@export var world: int = 0
## Which block of the stack holds the level (apparently unused).
@export var stack_position: int = 0
## Theme number (used when golden frogs unlock the next theme).
@export var theme: int = 0
## Position inside the world, 0 to 4.
@export var local_level: int = 0
## Number of levels in the world.
@export var levels_in_world: int = 0
## Texture record addresses: world selectable, world visited, world not tried,
## level screenshot, level name, in-game level name.
@export var image_pointers: PackedInt64Array = PackedInt64Array()
## True when the run-time area was not zero-filled (FrogLord refuses such a row).
@export var runtime_area_dirty: bool = false


## Reads one entry at [param reader]'s cursor (see [LevelSelectTableReader]).
static func read(reader: ByteReader) -> LevelSelectEntry:
	return LevelSelectTableReader.read_entry(reader)


## True for the row that ends a list.
func is_terminator() -> bool:
	return level == TERMINATOR_LEVEL
