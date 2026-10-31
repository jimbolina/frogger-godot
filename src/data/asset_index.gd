class_name AssetIndex
extends Resource
## What the importer wrote under [code]res://assets[/code] and where, saved as
## [code]catalog.tres[/code].
##
## It records the build the assets were imported from (with the SHA-256 of
## its executable and archive), the archive index, the asset file of every
## resource id that has one, the contents of every WAD, the counterpart of
## every incomplete model, the baked texture page sets and the levels the
## game can play. [ImportedAssets] answers [AssetCatalog] questions from it.

## The build's FrogLord internal name, for example [code]pc-retail-v3.0e[/code].
@export var version_name: String = ""
## SHA-256 of the executable the assets were imported from, lower-case hex.
@export var exe_sha256: String = ""
## SHA-256 of the MWD archive the assets were imported from, lower-case hex.
@export var mwd_sha256: String = ""
## The archive index.
@export var mwi: MwiIndex
## The decoded executable tables resource ([GameTables]).
@export var tables_path: String = ""
## FrogLord's name lists resource ([GameNameLists]).
@export var names_path: String = ""
## The asset file of each resource id that has one: texture banks, maps,
## sky-land tiles, models, sound banks and demos.
@export var paths: Dictionary[int, String] = {}
## Every WAD by resource id, its children listed without their bytes.
@export var wads: Dictionary[int, WadFile] = {}
## The complete model each incomplete model takes its shape from, by resource id.
@export var counterparts: Dictionary[int, int] = {}
## The baked [TexturePageSet] files by set name ([method TexturePageSet.name_for]).
@export var page_sets: Dictionary[String, String] = {}
## The codes of the levels the game plays, in level order.
@export var playable_levels: PackedStringArray = PackedStringArray()


## The asset file of resource [param resource_id], or "".
func path_of(resource_id: int) -> String:
	return paths.get(resource_id, "")


## The resource id of a WAD holding [param resource_id], or -1.
func wad_holding(resource_id: int) -> int:
	for wad_id: int in wads:
		for child: WadChild in wads[wad_id].children:
			if child.resource_id == resource_id:
				return wad_id
	return -1
