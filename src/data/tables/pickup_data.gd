class_name PickupData
extends Resource
## How one kind of bug (pickup) looks: glow colour, size and animation frames.
##
## The pickup table is one address per bug kind ([constant FroggerIds.FLY_SCORE_TYPES],
## 19 on PC). Each address points at (FrogLord's [code]FroggerPickupData[/code]):
## [codeblock]
## s32 glow colour (0x00BBGGRR)   s32 sprite size (16.16 fixed point, 0x10000 = 1.0)
## u32 texture record address per animation frame ... u32 0 (end)
## [/codeblock]

## Bug kind number (index into [constant FroggerIds.FLY_SCORE_TYPES]).
@export var fly_type: int = 0
## Address of this record in the program.
@export var pointer: int = 0
## Colour of the glow sphere, 0x00BBGGRR.
@export var glow_colour: int = 0
## Sprite scale in 16.16 fixed point.
@export var sprite_size: int = 0
## Texture record address of each animation frame.
@export var frame_pointers: PackedInt64Array = PackedInt64Array()


## Reads the whole pickup table of [param exe]. Sets [param problems] entries
## for anything unreadable; returns what could be read (see [PickupDataReader]).
static func read_table(exe: ExeImage, problems: PackedStringArray) -> Array[PickupData]:
	return PickupDataReader.read_table(exe, problems)


## The bug kind's name, e.g. "SCORE_100".
func fly_type_name() -> String:
	return FroggerIds.FLY_SCORE_TYPES[fly_type] if fly_type >= 0 and fly_type < FroggerIds.FLY_SCORE_TYPES.size() else ""
