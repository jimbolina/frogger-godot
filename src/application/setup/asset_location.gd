class_name AssetLocation
extends RefCounted
## Where the game reads its assets from: the base root holding the imported
## records, the shippable root holding the port's own fonts, lettering and
## emissive table, and the FrogLord overlay index when one is asked for.
##
## [method resolve] picks the base root in this order:
## [br]1. the folder given with [constant ASSETS_ROOT_ARGUMENT], used as given;
## [br]2. the [member LauncherSettings.imported_root] recorded in the launcher
## settings, when it holds an asset index;
## [br]3. the committed [constant ImportedAssets.SHIPPABLE_ROOT], when it holds
## an asset index.
## [br]When none is usable, [method is_usable] is false and [member error] says
## why; the setup screen then imports the player's files. The arguments and the
## launcher settings are inputs, so the order can be checked without a launch.

## The launch argument naming the base assets root.
const ASSETS_ROOT_ARGUMENT: String = "--assets-root="

## How the base root was chosen.
enum Origin { NONE, ARGUMENT, LAUNCHER, COMMITTED }

## The base folder the assets are read from, or "" when none is usable.
var base_root: String = ""
## The folder fonts, lettering and the emissive table are read from.
var shippable_root: String = ImportedAssets.SHIPPABLE_ROOT
## How [member base_root] was chosen.
var origin: Origin = Origin.NONE
## One line per candidate tried, with why it was or was not used.
var attempts := PackedStringArray()
## Non-fatal problems, such as a damaged launcher file, for the catalog's warnings.
var warnings := PackedStringArray()
## Why no base root is usable, or "".
var error: String = ""
## The FrogLord overlay pointer read by [method resolve_overlay], or null before one.
var overlay: FrogLordPointer = null


## Chooses the base root from [param arguments] (the launch's user arguments)
## and [param store] (the read launcher settings, or null for none), checking
## indexes under [param committed_root].
static func resolve(arguments: PackedStringArray, store: LauncherStore,
		committed_root: String = ImportedAssets.SHIPPABLE_ROOT) -> AssetLocation:
	var location := AssetLocation.new()
	if store != null and not store.error.is_empty():
		location.warnings.append(store.error)
	var requested: String = _argument(arguments)
	if not requested.is_empty():
		location._choose(requested, Origin.ARGUMENT)
		if not ImportedAssets.has_index(requested):
			location.error = "%s%s has no %s" % [ASSETS_ROOT_ARGUMENT, requested, ImportedAssets.INDEX_FILE]
		return location
	var imported: String = store.settings.imported_root if store != null else ""
	if imported.is_empty():
		location.attempts.append("launcher settings: no imported root recorded")
	elif ImportedAssets.has_index(imported):
		location._choose(imported, Origin.LAUNCHER)
		return location
	else:
		location.attempts.append("launcher settings: %s has no %s" % [imported, ImportedAssets.INDEX_FILE])
	if ImportedAssets.has_index(committed_root):
		location._choose(committed_root, Origin.COMMITTED)
		return location
	location.attempts.append("committed assets: %s has no %s" % [committed_root, ImportedAssets.INDEX_FILE])
	location.error = "no imported assets were found (%s)" % "; ".join(location.attempts)
	return location


## True when a base root holding an asset index was chosen.
func is_usable() -> bool:
	return not base_root.is_empty() and error.is_empty()


## The name of [member origin] for diagnostics.
func origin_name() -> String:
	match origin:
		Origin.ARGUMENT:
			return "argument"
		Origin.LAUNCHER:
			return "launcher settings"
		Origin.COMMITTED:
			return "committed assets"
	return "none"


## Reads the FrogLord pointer at [param pointer_path] into [member overlay] and
## returns it; [method FrogLordPointer.exists] is false when there is none.
func resolve_overlay(pointer_path: String = FrogLordPointer.DEFAULT_PATH) -> FrogLordPointer:
	overlay = FrogLordPointer.read(pointer_path)
	return overlay


## Opens the catalog over [member base_root] in the texture set called
## [param texture_set_name], with its index read from [param index_root] when
## that is not empty. The location's warnings join the catalog's. When no base
## root is usable, the catalog's [member AssetCatalog.error] is [member error].
func open(texture_set_name: String = "", index_root: String = "") -> ImportedAssets:
	if not is_usable():
		var unusable := ImportedAssets.new()
		unusable.shippable_root = shippable_root
		unusable.error = error
		unusable.warnings.append_array(warnings)
		return unusable
	var catalog: ImportedAssets = ImportedAssets.open(base_root, texture_set_name, index_root, shippable_root)
	catalog.warnings.append_array(warnings)
	return catalog


func _choose(root: String, chosen: Origin) -> void:
	base_root = root
	origin = chosen
	attempts.append("%s: %s" % [origin_name(), root])


static func _argument(arguments: PackedStringArray) -> String:
	for argument: String in arguments:
		if argument.begins_with(ASSETS_ROOT_ARGUMENT):
			return _normalised(argument.substr(ASSETS_ROOT_ARGUMENT.length()))
	return ""


static func _normalised(folder: String) -> String:
	var trimmed: String = folder.strip_edges()
	while trimmed.ends_with("/") and not trimmed.ends_with("://") and trimmed.length() > 1:
		trimmed = trimmed.substr(0, trimmed.length() - 1)
	return trimmed
