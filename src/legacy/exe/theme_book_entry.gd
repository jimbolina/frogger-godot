class_name ThemeBookEntry
extends RefCounted
## One theme's row in the theme book of the PC executable.
##
## A theme (Suburbia, Swamp, ...) names the texture banks (VLO files) and
## model bundles (WADs) shared by its levels, its form library and the height
## below which the frog drowns. The PC release has high- and low-poly
## variants, each with a single-player and a multiplayer version. Layout
## (FrogLord's [code]FroggerThemeBookPC[/code], 40 bytes):
## [codeblock]
## s32 high WAD id   u32 form library address   s32 high VLO id   s32 death height
## s32 high multiplayer WAD id   s32 high multiplayer VLO id
## s32 low WAD id    s32 low VLO id
## s32 low multiplayer WAD id    s32 low multiplayer VLO id
## [/codeblock]
## A zero id means "none". Only GENERAL has theme WADs on PC; other themes'
## models come from each level's own WAD.

## Size of a row in bytes.
const SIZE: int = 40

## Theme number, see [FroggerIds].
var theme: int = 0
## Resource id of the high-poly theme WAD.
var high_wad_id: int = 0
## Address of the theme's form library (0 = none).
var form_library_pointer: int = 0
## Resource id of the high-poly texture bank.
var high_vlo_id: int = 0
## The frog drowns below this height.
var death_height: int = 0
## Resource id of the high-poly multiplayer WAD.
var high_multiplayer_wad_id: int = 0
## Resource id of the high-poly multiplayer texture bank.
var high_multiplayer_vlo_id: int = 0
## Resource id of the low-poly theme WAD.
var low_wad_id: int = 0
## Resource id of the low-poly texture bank.
var low_vlo_id: int = 0
## Resource id of the low-poly multiplayer WAD.
var low_multiplayer_wad_id: int = 0
## Resource id of the low-poly multiplayer texture bank.
var low_multiplayer_vlo_id: int = 0
## The theme's forms, filled in by [ThemeBook].
var forms: Array[FormBookEntry] = []


## Reads one row at [param reader]'s cursor.
static func read(reader: ByteReader, theme_number: int) -> ThemeBookEntry:
	var t := ThemeBookEntry.new()
	t.theme = theme_number
	t.high_wad_id = reader.read_s32()
	t.form_library_pointer = reader.read_u32()
	t.high_vlo_id = reader.read_s32()
	t.death_height = reader.read_s32()
	t.high_multiplayer_wad_id = reader.read_s32()
	t.high_multiplayer_vlo_id = reader.read_s32()
	t.low_wad_id = reader.read_s32()
	t.low_vlo_id = reader.read_s32()
	t.low_multiplayer_wad_id = reader.read_s32()
	t.low_multiplayer_vlo_id = reader.read_s32()
	return t


## True when the theme has any data (FrogLord's test; RUINS has none on PC).
func is_valid() -> bool:
	return high_vlo_id != 0 or low_vlo_id != 0 or form_library_pointer != 0


## The texture bank resource id for the given mode (0 = none).
func vlo_id(multiplayer: bool = false, low_poly: bool = false) -> int:
	if multiplayer:
		return low_multiplayer_vlo_id if low_poly else high_multiplayer_vlo_id
	return low_vlo_id if low_poly else high_vlo_id


## The theme WAD resource id for the given mode (0 = none).
func wad_id(multiplayer: bool = false, low_poly: bool = false) -> int:
	if multiplayer:
		return low_multiplayer_wad_id if low_poly else high_multiplayer_wad_id
	return low_wad_id if low_poly else high_wad_id


## The theme's name, e.g. "SWAMP".
func theme_name() -> String:
	return FroggerIds.theme_name(theme)
