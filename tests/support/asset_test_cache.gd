class_name AssetTestCache
extends RefCounted
## The committed assets catalog and the reviewed overrides, read once per run
## and shared by every [AssetTest]. The static state lives here rather than in
## the inherited test base: Godot 4.5.1 on Windows crashes at exit when a
## script with static variables is inherited by a loaded script.

## Where the imported assets live.
const ASSETS: String = "res://assets"
## The reviewed hand edits of committed assets.
const OVERRIDES: String = "res://tests/golden/imported/overrides.tsv"

static var _catalog: ImportedAssets
static var _overrides: Dictionary[String, String] = {}
static var _overrides_read: bool = false


## The committed assets, opened on first use.
static func catalog() -> ImportedAssets:
	if _catalog == null:
		_catalog = ImportedAssets.open(ASSETS)
	return _catalog


## The reviewed override of [param field] of [param family] for [param asset]
## (a path under [code]assets/[/code]), or [param fallback] when none is recorded.
static func override(asset: String, family: String, field: String, fallback: String) -> String:
	if not _overrides_read:
		_overrides_read = true
		for row: PackedStringArray in _read_overrides():
			_overrides["%s\t%s\t%s" % [row[0], row[1], row[2]]] = row[3]
	return _overrides.get("%s\t%s\t%s" % [asset, family, field], fallback)


static func _read_overrides() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for line: String in FileAccess.get_file_as_string(OVERRIDES).split("\n", false):
		if line.begins_with("#"):
			continue
		var row: PackedStringArray = line.split("\t")
		if row.size() >= 5 and not row[4].strip_edges().is_empty():
			rows.append(row)
	return rows
