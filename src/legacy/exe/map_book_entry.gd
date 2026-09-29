class_name MapBookEntry
extends RefCounted
## One level's row in the level list ("map book") of the PC executable.
##
## The PC release ships every level twice: a detailed ("high-poly") version
## and a simpler one for slow machines ("low-poly", the [code]_WIN95[/code]
## files). Each row names both versions' map file, texture remap and WAD of
## models. The layout is FrogLord's [code]FroggerMapBookPC[/code], 36 bytes:
## [codeblock]
## s32 high map id    s32 low map id    (MWI resource ids of the .MAP files)
## u32 high remap     u32 low remap     (addresses of the texture remaps)
## s32 cave lights    (1 = the cave lighting model)
## u32 environment texture (address of a texture record, 0 = none)
## s32 high WAD id    s32 low WAD id    s32 palette id
## [/codeblock]
## Unused levels have zero ids; FrogLord calls a row "dummy" when both remap
## addresses are zero.

## Size of a row in bytes.
const SIZE: int = 36

## Level number (row position), see [FroggerIds].
var level: int = 0
## Resource id of the high-poly map.
var high_map_id: int = 0
## Resource id of the low-poly map.
var low_map_id: int = 0
## Address of the high-poly map's texture remap (0 = none).
var high_remap_pointer: int = 0
## Address of the low-poly map's texture remap (0 = none).
var low_remap_pointer: int = 0
## True when the level uses cave lighting (the stored value is exactly 1).
var use_cave_lights: bool = false
## Address of the environment-map texture record (0 = none).
var environment_texture_pointer: int = 0
## Resource id of the high-poly level WAD.
var high_wad_id: int = 0
## Resource id of the low-poly level WAD.
var low_wad_id: int = 0
## Resource id of the level's palette file.
var palette_id: int = 0


## Reads one row at [param reader]'s cursor.
static func read(reader: ByteReader, level_number: int) -> MapBookEntry:
	var e := MapBookEntry.new()
	e.level = level_number
	e.high_map_id = reader.read_s32()
	e.low_map_id = reader.read_s32()
	e.high_remap_pointer = reader.read_u32()
	e.low_remap_pointer = reader.read_u32()
	e.use_cave_lights = reader.read_s32() == 1
	e.environment_texture_pointer = reader.read_u32()
	e.high_wad_id = reader.read_s32()
	e.low_wad_id = reader.read_s32()
	e.palette_id = reader.read_s32()
	return e


## True when FrogLord treats the row as an unused level (no remaps at all).
func is_dummy() -> bool:
	return high_remap_pointer == 0 and low_remap_pointer == 0


## The map resource id for the chosen detail level.
func map_id(low_poly: bool = false) -> int:
	return low_map_id if low_poly else high_map_id


## The level WAD resource id for the chosen detail level.
func wad_id(low_poly: bool = false) -> int:
	return low_wad_id if low_poly else high_wad_id


## The texture remap address for the chosen detail level.
func remap_pointer(low_poly: bool = false) -> int:
	return low_remap_pointer if low_poly else high_remap_pointer


## The level's code, e.g. "SUB1".
func code() -> String:
	return FroggerIds.level_code(level)
