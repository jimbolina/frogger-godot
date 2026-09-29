class_name FrogLordModSource
extends GameDataSource
## Game files saved by FrogLord: [code]modded_FROGGER.EXE[/code] and [code]modded_FROGPSX.MWD[/code].
##
## FrogLord's "Save" writes a patched executable and archive with a
## [code]modded_[/code] prefix, plus a standalone copy of the archive index
## ([code]modded_FROGPSX.MWI[/code]) for reference. The executable carries the
## same index the game reads, and a [FrogLordExeTrailer] naming the build it
## was made from.

## Executable name FrogLord saves.
const EXE_NAME: String = "modded_FROGGER.EXE"
## Archive name FrogLord saves.
const MWD_NAME: String = "modded_FROGPSX.MWD"
## Standalone index FrogLord saves next to the executable (optional).
const MWI_NAME: String = "modded_FROGPSX.MWI"

var _trailer: FrogLordExeTrailer
var _trailer_read: bool = false


## True if [param dir] holds FrogLord's modded executable and archive.
static func looks_like(dir: String) -> bool:
	return not find_file_ignoring_case(dir, EXE_NAME).is_empty() \
		and not find_file_ignoring_case(dir, MWD_NAME).is_empty()


func kind_name() -> String:
	return "FrogLord mod"


func exe_file_name() -> String:
	return EXE_NAME


func mwd_file_name() -> String:
	return MWD_NAME


func get_exe_path() -> String:
	return find_file_ignoring_case(directory, EXE_NAME)


func get_mwd_path() -> String:
	return find_file_ignoring_case(directory, MWD_NAME)


## Path of the standalone index FrogLord wrote, or "" if there is none.
func get_standalone_mwi_path() -> String:
	return find_file_ignoring_case(directory, MWI_NAME)


## The FrogLord trailer of the executable; null if the executable has none.
func get_trailer() -> FrogLordExeTrailer:
	if not _trailer_read:
		_trailer = FrogLordExeTrailer.read(get_exe_bytes())
		_trailer_read = true
	return _trailer


func fingerprint_paths() -> PackedStringArray:
	var paths: PackedStringArray = super.fingerprint_paths()
	var mwi: String = get_standalone_mwi_path()
	if not mwi.is_empty():
		paths.append(mwi)
	return paths


func describe() -> String:
	var trailer: FrogLordExeTrailer = get_trailer()
	if trailer != null and trailer.error.is_empty():
		return "%s in %s (saved by FrogLord %d from %s)" % [kind_name(), directory, trailer.froglord_version, trailer.game_version]
	return super.describe()
