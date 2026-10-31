class_name GameVersionConfig
extends RefCounted
## What is known about one build of Frogger, from its FrogLord version file.
##
## Each build of the game keeps its tables (level list, theme list, music
## list, scripts, ...) at different places in its executable. FrogLord records
## those places per build in [code]versions/<build>.cfg[/code]; this class is
## a typed view of such a file.
##
## Table locations ([member map_book], [member theme_book], ...) are [b]file
## offsets[/b] into the executable. Pointers stored [i]inside[/i] the tables are
## addresses in the running program; [method pointer_to_file_offset] converts
## them using [member ram_offset], exactly as FrogLord does.
##
## When a version file leaves out the form, entity or script list, FrogLord
## falls back to fixed defaults; those defaults are applied here too.

## FrogLord's default form list for Frogger builds that do not name one.
const DEFAULT_FORM_LIST: String = "1997-09-12-psx-build57"
## FrogLord's default entity list for Frogger builds that do not name one.
const DEFAULT_ENTITY_LIST: String = "1997-09-12-psx-build57"
## FrogLord's default script list for Frogger builds that do not name one.
const DEFAULT_SCRIPT_LIST: String = "1997-09-18-psx-build63"

## File name without extension, e.g. "pc-retail-v3.0e". FrogLord calls it the internal name.
var internal_name: String = ""
## Human-readable name, e.g. "PC Retail v3.0e (Worldwide?)".
var display_name: String = ""
## "WINDOWS" or "PLAYSTATION".
var platform: String = ""
## Build timestamp text as written in the config, if any.
var build_time: String = ""
## CRC-32 values of the unmodified executable(s) of this build.
var exe_checksums: PackedInt64Array = PackedInt64Array()
## Build number for PlayStation development builds, -1 if not given.
var build: int = -1
## File offset of the MWI (the archive index) inside the executable.
var mwi_offset: int = 0
## Size in bytes of the MWI inside the executable.
var mwi_length: int = 0
## Added to a file offset gives the in-memory address (0 if not configured).
var ram_offset: int = 0
## File offset of the level ("map book") table, -1 if unknown.
var map_book: int = -1
## File offset of the theme book table, -1 if unknown.
var theme_book: int = -1
## File offset of the arcade level order table, 0 if unknown.
var arcade_level_address: int = 0
## File offset of the music track table, -1 if unknown.
var music_address: int = -1
## File offset of the texture pointer list, 0 if unknown.
var bmp_pointer_address: int = 0
## The "extraBmpPointers" flag some builds set, 0 if absent.
var extra_bmp_pointers: int = 0
## File offset of the pickup (bug) data table, 0 if unknown.
var pickup_data: int = 0
## File offset of the script pointer table, 0 if unknown.
var scripts: int = 0
## File offset of the sky texture remap, 0 if unknown.
var txl_sky_land: int = 0
## Name of the animation name list (anims/), "" if none.
var anim_list: String = ""
## Name of the sound name list (sounds/), "" if none.
var sound_list: String = ""
## Name of the texture name list (images/), "" if none.
var image_list: String = ""
## Name of the texture group tree (vlo/), "" if none.
var vlo_tree: String = ""
## Name of the form name list (forms/).
var form_list: String = DEFAULT_FORM_LIST
## Name of the entity name list (entities/).
var entity_list: String = DEFAULT_ENTITY_LIST
## Name of the script name list (scripts/).
var script_list: String = DEFAULT_SCRIPT_LIST
## Model file name to the part numbers FrogLord hides when showing it.
var hidden_parts: Dictionary[String, PackedInt64Array] = {}
## Problems met while reading the config; empty when it is usable.
var errors: PackedStringArray = PackedStringArray()
## The parsed config the fields were read from.
var source_config: FrogLordConfig


## Reads the typed fields out of [param config], a version file parsed with
## [LegacyConfigParser]. [param name_without_extension] becomes [member internal_name].
static func from_config(config: FrogLordConfig, name_without_extension: String) -> GameVersionConfig:
	var v := GameVersionConfig.new()
	v.source_config = config
	v.internal_name = name_without_extension
	v.display_name = config.get_string("name")
	v.platform = config.get_string("platform")
	v.build_time = config.get_string("buildTime")
	v._read_checksums(config)
	v.build = v._int(config, "build", -1)
	v.mwi_offset = v._required_int(config, "mwiOffset")
	v.mwi_length = v._required_int(config, "mwiLength")
	v.ram_offset = v._int(config, "ramOffset", 0)
	v.map_book = v._int(config, "mapBook", -1)
	v.theme_book = v._int(config, "themeBook", -1)
	v.arcade_level_address = v._int(config, "arcadeLevelAddress", 0)
	v.music_address = v._int(config, "musicAddress", -1)
	v.bmp_pointer_address = v._int(config, "bmpPointerAddress", 0)
	v.extra_bmp_pointers = v._int(config, "extraBmpPointers", 0)
	v.pickup_data = v._int(config, "pickupData", 0)
	v.scripts = v._int(config, "scripts", 0)
	v.txl_sky_land = v._int(config, "txl_sky_land", 0)
	v.anim_list = config.get_string("animList")
	v.sound_list = config.get_string("soundList")
	v.image_list = config.get_string("imageList")
	v.vlo_tree = config.get_string("vloTree")
	v.form_list = config.get_string("formList", DEFAULT_FORM_LIST)
	v.entity_list = config.get_string("entityList", DEFAULT_ENTITY_LIST)
	v.script_list = config.get_string("scriptList", DEFAULT_SCRIPT_LIST)
	if v.display_name.is_empty():
		v.errors.append("missing 'name'")
	var parts: FrogLordConfig = config.get_child("HiddenParts")
	if parts != null:
		for key: String in parts.keys():
			v.hidden_parts[key] = parts.get_int_array(key)
	return v


## True when the config had everything needed to open the game's archives.
func is_valid() -> bool:
	return errors.is_empty()


## True for Windows builds.
func is_pc() -> bool:
	return platform == "WINDOWS"


## True if [param crc] (CRC-32 of a whole executable) identifies this build.
func matches_exe_checksum(crc: int) -> bool:
	return exe_checksums.has(crc)


## Converts an address found inside the executable's data (a pointer as the
## running game saw it) to a file offset in the executable.
func pointer_to_file_offset(pointer: int) -> int:
	return pointer - ram_offset


## Converts an executable file offset to the address the running game used.
func file_offset_to_pointer(file_offset: int) -> int:
	return file_offset + ram_offset


## The name lists this build refers to, as "folder/name" pairs, for example
## "sounds" -> "1997-11-19-pc-retail". Lists the build does not name are left out.
func referenced_name_lists() -> Dictionary[String, String]:
	var lists: Dictionary[String, String] = {}
	for pair: Array in [["anims", anim_list], ["sounds", sound_list], ["images", image_list],
			["vlo", vlo_tree], ["forms", form_list], ["entities", entity_list], ["scripts", script_list]]:
		var list_name: String = pair[1]
		if not list_name.is_empty():
			var folder: String = pair[0]
			lists[folder] = list_name
	return lists


func _read_checksums(config: FrogLordConfig) -> void:
	var raw: String = config.get_string("exeChecksum").strip_edges()
	if raw.is_empty():
		return
	for part: String in raw.split(","):
		var text: String = part.strip_edges()
		if text.is_valid_int():
			exe_checksums.append(text.to_int())
		else:
			errors.append("exeChecksum entry '%s' is not a number" % text)


func _int(config: FrogLordConfig, key: String, fallback: int) -> int:
	if config.has_key(key) and not config.has_valid_int(key):
		errors.append("'%s' is not a number: '%s'" % [key, config.get_string(key)])
	return config.get_int(key, fallback)


func _required_int(config: FrogLordConfig, key: String) -> int:
	if not config.has_key(key):
		errors.append("missing '%s'" % key)
		return 0
	return _int(config, key, 0)
