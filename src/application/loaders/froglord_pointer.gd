class_name FrogLordPointer
extends RefCounted
## The file naming the newest overlay imported from a FrogLord save, by
## [code]archive/import/froglord_watch.sh[/code] or the in-game watcher, which
## a game following FrogLord opens and reloads.
##
## The file is a [ConfigFile] with one section, [code][overlay][/code], holding
## the fields below. [method write] writes a temporary file beside the target
## and renames it over the target, so a reader never sees half a file.

## The pointer file the watcher writes and the game reads.
const DEFAULT_PATH: String = "user://froglord/current.cfg"
const _SECTION: String = "overlay"
const _TEMP_SUFFIX: String = ".tmp"

## The folder holding the overlay's [code]catalog.tres[/code].
var index_root: String = ""
## The key of the FrogLord save the overlay was imported from: the first 16 hex
## digits of [method GameDataSource.fingerprint], which also name the folder.
var fingerprint: String = ""
## [method ImportedAssets.source_summary] of the overlay.
var source_summary: String = ""
## The overlay's [code]support_report.tsv[/code].
var report_path: String = ""
## When the watcher wrote the pointer, in Unix seconds.
var written_at: int = 0
## The save folder the overlay was imported from.
var data_dir: String = ""
## The base root the overlay's index falls back to.
var fallback_root: String = ""
## The save files' state when the import began, as
## [code]AssetImporter.source_state[/code] gives it.
var source_state: String = ""

var _exists: bool = false


## The pointer at [param path]; every field empty and [method exists] false
## when the file is absent or cannot be read.
static func read(path: String = DEFAULT_PATH) -> FrogLordPointer:
	var pointer := FrogLordPointer.new()
	if not FileAccess.file_exists(path):
		return pointer
	var file := ConfigFile.new()
	if file.load(path) != OK or not file.has_section(_SECTION):
		return pointer
	pointer.index_root = str(file.get_value(_SECTION, "index_root", ""))
	pointer.fingerprint = str(file.get_value(_SECTION, "fingerprint", ""))
	pointer.source_summary = str(file.get_value(_SECTION, "source_summary", ""))
	pointer.report_path = str(file.get_value(_SECTION, "report_path", ""))
	var stamp: Variant = file.get_value(_SECTION, "written_at", 0)
	pointer.written_at = stamp if stamp is int else 0
	pointer.data_dir = str(file.get_value(_SECTION, "data_dir", ""))
	pointer.fallback_root = str(file.get_value(_SECTION, "fallback_root", ""))
	pointer.source_state = str(file.get_value(_SECTION, "source_state", ""))
	pointer._exists = not pointer.index_root.is_empty()
	return pointer


## The modification time of [param path] in Unix seconds, or 0 when it is absent.
static func modified_time(path: String = DEFAULT_PATH) -> int:
	if not FileAccess.file_exists(path):
		return 0
	return FileAccess.get_modified_time(path)


## True when the pointer was read from a file naming an index root.
func exists() -> bool:
	return _exists


## Writes the pointer to [param path], creating its folder, through a
## temporary file renamed over the target.
func write(path: String = DEFAULT_PATH) -> Error:
	var made: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if made != OK:
		return made
	var file := ConfigFile.new()
	file.set_value(_SECTION, "index_root", index_root)
	file.set_value(_SECTION, "fingerprint", fingerprint)
	file.set_value(_SECTION, "source_summary", source_summary)
	file.set_value(_SECTION, "report_path", report_path)
	file.set_value(_SECTION, "written_at", written_at)
	file.set_value(_SECTION, "data_dir", data_dir)
	file.set_value(_SECTION, "fallback_root", fallback_root)
	file.set_value(_SECTION, "source_state", source_state)
	var temporary: String = path + _TEMP_SUFFIX
	var saved: Error = file.save(temporary)
	if saved != OK:
		return saved
	var renamed: Error = DirAccess.rename_absolute(temporary, path)
	if renamed != OK:
		DirAccess.remove_absolute(temporary)
		return renamed
	_exists = not index_root.is_empty()
	return OK
