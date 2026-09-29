class_name GameDataSource
extends RefCounted
## Where the game's data comes from: an executable plus its asset archive.
##
## Frogger's PC data is two files: the executable ([code]FROGGER.EXE[/code]),
## which also holds the archive index (the MWI) and many game tables, and the
## archive ([code]FROGPSX.MWD[/code]) holding every model, texture, map and
## sound. Subclasses say which files those are in a folder: an untouched
## retail install ([RetailDirSource]) or files saved by FrogLord
## ([FrogLordModSource]).
##
## This project never ships any of these bytes; they are always read from the
## player's own copy.

## The folder the files are in.
var directory: String = ""

var _exe_bytes: PackedByteArray = PackedByteArray()
var _exe_loaded: bool = false


## A source for the files in [param dir].
func _init(dir: String) -> void:
	directory = dir


## Short name of the source kind, e.g. "retail install".
func kind_name() -> String:
	return "game data"


## Full path of the executable, or "" if it is missing.
func get_exe_path() -> String:
	return ""


## Full path of the MWD archive, or "" if it is missing.
func get_mwd_path() -> String:
	return ""


## True when every required file is present.
func is_complete() -> bool:
	return missing_files().is_empty()


## Names of required files that are not in the folder.
func missing_files() -> PackedStringArray:
	var missing := PackedStringArray()
	if get_exe_path().is_empty():
		missing.append(exe_file_name())
	if get_mwd_path().is_empty():
		missing.append(mwd_file_name())
	return missing


## Expected file name of the executable.
func exe_file_name() -> String:
	return ""


## Expected file name of the MWD archive.
func mwd_file_name() -> String:
	return ""


## The whole executable, read once and kept (it is under 1 MB).
func get_exe_bytes() -> PackedByteArray:
	if not _exe_loaded:
		var path: String = get_exe_path()
		if not path.is_empty():
			_exe_bytes = FileAccess.get_file_as_bytes(path)
		_exe_loaded = true
	return _exe_bytes


## Opens the MWD archive for reading; null if it cannot be opened. The archive
## is 16 MB, so callers read from it by seeking rather than loading it whole.
func open_mwd() -> FileAccess:
	var path: String = get_mwd_path()
	if path.is_empty():
		return null
	return FileAccess.open(path, FileAccess.READ)


## The MWI (archive index) bytes for [param version]: the region of the
## executable the version config names. The game itself reads it from there.
func get_mwi_bytes(version: GameVersionConfig) -> PackedByteArray:
	var exe: PackedByteArray = get_exe_bytes()
	if version.mwi_offset <= 0 or version.mwi_offset + version.mwi_length > exe.size():
		return PackedByteArray()
	return exe.slice(version.mwi_offset, version.mwi_offset + version.mwi_length)


## A SHA-256 over the contents of every file this source reads, as hex. It
## changes whenever FrogLord saves any of them, so it can key caches of
## converted assets.
func fingerprint() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for path: String in fingerprint_paths():
		ctx.update(path.get_file().to_lower().to_utf8_buffer())
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		while file.get_position() < file.get_length():
			ctx.update(file.get_buffer(1 << 20))
	return ctx.finish().hex_encode()


## The files [method fingerprint] covers.
func fingerprint_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for path: String in [get_exe_path(), get_mwd_path()]:
		if not path.is_empty():
			paths.append(path)
	return paths


## One line for people: what kind of source this is and where.
func describe() -> String:
	return "%s in %s" % [kind_name(), directory]


## Finds [param file_name] in [param dir] ignoring letter case (a Windows
## install copied to Linux may have any case). Returns the full path or "".
static func find_file_ignoring_case(dir: String, file_name: String) -> String:
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		return ""
	var exact: String = dir.path_join(file_name)
	if FileAccess.file_exists(exact):
		return exact
	var wanted: String = file_name.to_lower()
	for candidate: String in DirAccess.get_files_at(dir):
		if candidate.to_lower() == wanted:
			return dir.path_join(candidate)
	return ""
