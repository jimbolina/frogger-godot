class_name FrogLordConfigLibrary
extends RefCounted
## Finds and loads the FrogLord configuration files shipped with this project.
##
## The files live unmodified under [code]archive/third_party/froglord_cfg/[/code] with
## FrogLord's own layout: [code]versions/[/code] for builds, and
## [code]sounds/[/code], [code]forms/[/code], [code]entities/[/code],
## [code]scripts/[/code], [code]anims/[/code], [code]images/[/code] and
## [code]vlo/[/code] for name lists.

## Where the shipped FrogLord files are.
const DEFAULT_ROOT: String = "res://archive/third_party/froglord_cfg"

## Folder this library reads from.
var root: String = DEFAULT_ROOT
## Why the last load failed, or "".
var error: String = ""

var _version_cache: Dictionary[String, GameVersionConfig] = {}


## A library reading from [param root_dir] (the shipped files by default).
func _init(root_dir: String = DEFAULT_ROOT) -> void:
	root = root_dir


## Internal names of every build with a version file, sorted.
func version_names() -> PackedStringArray:
	var names := PackedStringArray()
	for file: String in DirAccess.get_files_at(root.path_join("versions")):
		if file.get_extension().to_lower() == "cfg":
			names.append(file.get_basename())
	names.sort()
	return names


## The build called [param internal_name] (e.g. "pc-retail-v3.0e"), or null.
func load_version(internal_name: String) -> GameVersionConfig:
	if _version_cache.has(internal_name):
		return _version_cache[internal_name]
	var config: FrogLordConfig = load_config("versions", internal_name)
	if config == null:
		return null
	var version: GameVersionConfig = GameVersionConfig.from_config(config, internal_name)
	_version_cache[internal_name] = version
	return version


## Every build whose version file lists [param crc] as an executable checksum.
func find_versions_by_exe_checksum(crc: int) -> Array[GameVersionConfig]:
	var found: Array[GameVersionConfig] = []
	for version_name: String in version_names():
		var version: GameVersionConfig = load_version(version_name)
		if version != null and version.matches_exe_checksum(crc):
			found.append(version)
	return found


## Parses [code]<folder>/<file_name>.cfg[/code] with the older FrogLord reader.
func load_config(folder: String, file_name: String) -> FrogLordConfig:
	error = ""
	var path: String = root.path_join(folder).path_join(file_name + ".cfg")
	if not FileAccess.file_exists(path):
		error = "no FrogLord config at %s" % path
		return null
	var parser := LegacyConfigParser.new()
	var config: FrogLordConfig = parser.parse(FileAccess.get_file_as_string(path), file_name)
	if config == null:
		error = "%s: %s" % [path, parser.error]
	return config


## Loads a list-style name bank (sounds, forms, entities, scripts, anims).
## Script lists keep their sections separate, as FrogLord does.
func load_name_bank(folder: String, file_name: String) -> NameBank:
	var config: FrogLordConfig = load_config(folder, file_name)
	if config == null:
		return null
	var label: String = {"sounds": "Sound", "forms": "Form", "entities": "Entity",
		"scripts": "Script", "anims": "Animation"}.get(folder, folder)
	return NameBankReader.from_list_config(config, folder != "scripts", label)


## Loads a texture name list ([code]images/<file_name>.cfg[/code], id=name pairs).
func load_image_names(file_name: String) -> NameBank:
	var config: FrogLordConfig = load_config("images", file_name)
	if config == null:
		return null
	return NameBankReader.from_indexed_config(config, "Image")
