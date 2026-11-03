class_name AssetImporterFactory
extends RefCounted
## Gives the game its [AssetImporter]. This is the one script outside
## [code]archive/[/code] allowed to reach the archive: it loads the importer's
## runtime adapter, [code]archive/import/runtime_import.gd[/code], only when an
## importer is asked for, so nothing is loaded from the archive before then.


## A new importer, or the interface's own inert one (whose
## [method AssetImporter.detect] and [method AssetImporter.run] report that
## no importer is available) when the adapter does not load.
static func create() -> AssetImporter:
	var script: GDScript = load("res://archive/import/runtime_import.gd") as GDScript
	if script == null or not script.can_instantiate():
		return AssetImporter.new()
	var importer: AssetImporter = script.new()
	return importer
