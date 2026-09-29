class_name FrogLordExeTrailer
extends RefCounted
## The build information FrogLord appends to a Windows executable it saves.
##
## When FrogLord saves a modded [code]FROGGER.EXE[/code] it appends, after the
## original program bytes:
## [codeblock]
## [config text, UTF-8][0x00][format version: u8][original exe length: s32 LE]["FROGLORD"]
## [/codeblock]
## The config text is in FrogLord's newer config dialect and holds a
## [code][BuildInfo][/code] section with [code]gameType[/code] (e.g. "frogger"),
## [code]gameVersion[/code] (the internal name of the build it was made from,
## e.g. "pc-retail-v3.0e") and [code]frogLordVersion[/code]. A modded
## executable's checksum no longer matches any known build, so this is how
## its version is recognised.
##
## Layout and checks follow FrogLord's [code]FileUtils.loadConfigDataFromExecutable[/code].

## The 8-byte marker at the very end of a FrogLord-saved executable.
const SIGNATURE: String = "FROGLORD"
## Newest trailer format this reader understands (FrogLord's current value).
const SUPPORTED_FORMAT_VERSION: int = 0
## Bytes after the config text's terminator: version, length, signature.
const FOOTER_SIZE: int = 1 + 4 + 8

## Trailer format version found in the file.
var format_version: int = 0
## Size of the executable before FrogLord appended the trailer.
var original_exe_length: int = 0
## The appended config text.
var config_text: String = ""
## [member config_text] parsed; null if it did not parse.
var config: FrogLordConfig
## "gameType" from the BuildInfo section, e.g. "frogger".
var game_type: String = ""
## "gameVersion" from the BuildInfo section, e.g. "pc-retail-v3.0e".
var game_version: String = ""
## "frogLordVersion" from the BuildInfo section, -1 if absent.
var froglord_version: int = -1
## Why the trailer is unusable, or "" when it read cleanly.
var error: String = ""


## True if [param exe] ends with the FROGLORD signature.
static func is_present(exe: PackedByteArray) -> bool:
	if exe.size() < 16:
		return false
	return exe.slice(exe.size() - SIGNATURE.length()) == SIGNATURE.to_ascii_buffer()


## Reads the trailer of [param exe]. Returns null when there is none; returns
## a trailer with [member error] set when one is present but unusable.
static func read(exe: PackedByteArray) -> FrogLordExeTrailer:
	if not is_present(exe):
		return null
	var t := FrogLordExeTrailer.new()
	if exe.slice(0, 2).get_string_from_ascii() != "MZ":
		t.error = "not a Windows executable (no MZ header)"
		return t
	var footer_at: int = exe.size() - FOOTER_SIZE
	t.format_version = exe.decode_u8(footer_at)
	t.original_exe_length = exe.decode_s32(footer_at + 1)
	if t.format_version > SUPPORTED_FORMAT_VERSION:
		t.error = "saved by a newer FrogLord (trailer format %d, this game reads up to %d)" % [
			t.format_version, SUPPORTED_FORMAT_VERSION]
		return t
	if t.original_exe_length < 0 or t.original_exe_length > footer_at:
		t.error = "original length %d does not fit an executable of %d bytes" % [t.original_exe_length, exe.size()]
		return t
	var text_bytes: PackedByteArray = exe.slice(t.original_exe_length, footer_at + 1)
	var nul_at: int = text_bytes.find(0)
	if nul_at >= 0:
		text_bytes = text_bytes.slice(0, nul_at)
	t.config_text = text_bytes.get_string_from_utf8()
	var parser := ModernConfigParser.new()
	t.config = parser.parse(t.config_text, "BuildInfo")
	if t.config == null:
		t.error = "build information does not parse: %s" % parser.error
		return t
	var info: FrogLordConfig = t.config.get_child("BuildInfo")
	if info == null:
		t.error = "no [BuildInfo] section in the build information"
		return t
	t.game_type = info.get_string("gameType")
	t.game_version = info.get_string("gameVersion")
	t.froglord_version = info.get_int("frogLordVersion", -1)
	if t.game_version.is_empty():
		t.error = "[BuildInfo] has no gameVersion"
	return t


## Builds the bytes FrogLord would append for [param build_info_text] after an
## executable of [param original_length] bytes. Used by tests to make
## synthetic modded executables.
static func build_footer(build_info_text: String, original_length: int, format: int = SUPPORTED_FORMAT_VERSION) -> PackedByteArray:
	var out: PackedByteArray = build_info_text.to_utf8_buffer()
	out.append(0)
	out.append(format)
	var length_bytes := PackedByteArray()
	length_bytes.resize(4)
	length_bytes.encode_s32(0, original_length)
	out.append_array(length_bytes)
	out.append_array(SIGNATURE.to_ascii_buffer())
	return out
