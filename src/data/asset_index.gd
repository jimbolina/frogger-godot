class_name AssetIndex
extends Resource
## What the importer wrote under an asset root and where, saved as
## [code]catalog.tres[/code].
##
## It records the build the assets were imported from, the kind of source
## (the retail files or a FrogLord save) with its file names, the SHA-256 of
## its executable and archive, the archive index, the asset file of every
## resource id that has one, the contents of every WAD, the counterpart of
## every incomplete model, the model parts FrogLord's settings hide and the
## levels the game can play.
## An overlay index, written outside the committed root, also records the
## complete root it falls back to; its paths point into either root.
## [ImportedAssets] answers [AssetCatalog] questions from it.

## [member source_kind] of an unmodified retail install.
const SOURCE_RETAIL: String = "retail"
## [member source_kind] of files saved by FrogLord.
const SOURCE_FROGLORD_MOD: String = "FrogLord mod"

## The build's FrogLord internal name, for example [code]pc-retail-v3.0e[/code].
@export var version_name: String = ""
## SHA-256 of the executable the assets were imported from, lower-case hex.
@export var exe_sha256: String = ""
## SHA-256 of the MWD archive the assets were imported from, lower-case hex.
@export var mwd_sha256: String = ""
## The kind of source the assets were imported from: [constant SOURCE_RETAIL]
## or [constant SOURCE_FROGLORD_MOD].
@export var source_kind: String = SOURCE_RETAIL
## The executable's file name, for example [code]FROGGER.EXE[/code].
@export var source_exe_name: String = ""
## The archive's file name, for example [code]FROGPSX.MWD[/code].
@export var source_mwd_name: String = ""
## The build a FrogLord save names in its executable's trailer, or "".
@export var trailer_build: String = ""
## The FrogLord version that saved the source, or -1.
@export var froglord_version: int = -1
## The complete asset root an overlay index falls back to, or "" for a
## complete index.
@export var fallback_root: String = ""
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
## The parts FrogLord's settings hide, as part indices by model file name.
@export var hidden_parts: Dictionary[String, PackedInt64Array] = {}
## The codes of the levels the game plays, in level-number order.
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
