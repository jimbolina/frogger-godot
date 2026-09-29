class_name GameVersionDetector
extends RefCounted
## Works out which build of Frogger an executable is, the way FrogLord does.
##
## 1. If the executable ends with FrogLord's trailer ([FrogLordExeTrailer]),
##    its [code]gameVersion[/code] names the build directly. A modded
##    executable's checksum matches nothing, so this comes first.
## 2. Otherwise the CRC-32 of the whole file is looked up in the
##    [code]exeChecksum[/code] lists of the shipped version files.

## Detection used the FrogLord trailer.
const METHOD_TRAILER: String = "FrogLord build information"
## Detection used the executable's CRC-32.
const METHOD_CHECKSUM: String = "executable checksum"


## The outcome of one detection.
class Result:
	extends RefCounted
	## The detected build, or null.
	var version: GameVersionConfig
	## [constant METHOD_TRAILER] or [constant METHOD_CHECKSUM]; "" on failure.
	var method: String = ""
	## CRC-32 of the whole executable as read.
	var exe_crc32: int = 0
	## Why detection failed, or "".
	var error: String = ""

	## True when a build was found.
	func is_ok() -> bool:
		return version != null and error.is_empty()


var _library: FrogLordConfigLibrary


## A detector that looks builds up in [param library].
func _init(library: FrogLordConfigLibrary) -> void:
	_library = library


## Identifies the build of the executable bytes [param exe].
func detect(exe: PackedByteArray) -> Result:
	var result := Result.new()
	if exe.is_empty():
		result.error = "the executable is empty or unreadable"
		return result
	result.exe_crc32 = Crc32.of_bytes(exe)
	var trailer: FrogLordExeTrailer = FrogLordExeTrailer.read(exe)
	if trailer != null:
		return _from_trailer(trailer, result)
	var matches: Array[GameVersionConfig] = _library.find_versions_by_exe_checksum(result.exe_crc32)
	if matches.is_empty():
		result.error = "unknown executable (CRC-32 %d); no FrogLord version file lists it" % result.exe_crc32
		return result
	result.version = matches[0]
	result.method = METHOD_CHECKSUM
	return result


func _from_trailer(trailer: FrogLordExeTrailer, result: Result) -> Result:
	if not trailer.error.is_empty():
		result.error = "FrogLord build information: %s" % trailer.error
		return result
	if not trailer.game_type.is_empty() and trailer.game_type.to_lower() != "frogger":
		result.error = "this executable was saved by FrogLord for '%s', not Frogger" % trailer.game_type
		return result
	var version: GameVersionConfig = _library.load_version(trailer.game_version)
	if version == null:
		result.error = "FrogLord says this is build '%s', which has no version file here" % trailer.game_version
		return result
	result.version = version
	result.method = METHOD_TRAILER
	return result
