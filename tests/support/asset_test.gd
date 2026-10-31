class_name AssetTest
extends GutTest
## Base of the import goldens under [code]tests/golden/assets/[/code]: opens the
## committed assets as an [ImportedAssets] catalog (once per run) and reads the
## retail facts and reviewed overrides they are compared with.

## Where the imported assets live.
const ASSETS: String = "res://assets"
## The reviewed hand edits of committed assets.
const OVERRIDES: String = "res://tests/golden/imported/overrides.tsv"

static var _catalog: ImportedAssets
static var _overrides: Dictionary[String, String] = {}
static var _overrides_read: bool = false


## The committed assets, opened once and shared by every asset test.
func catalog() -> ImportedAssets:
	if _catalog == null:
		_catalog = ImportedAssets.open(ASSETS)
	return _catalog


## Rows of the golden TSV [param file_name] (comment lines dropped).
func fact_rows(file_name: String) -> Array[PackedStringArray]:
	return GoldenFiles.rows(file_name)


## The key=value facts of the golden text file [param file_name].
func fact_values(file_name: String) -> Dictionary[String, String]:
	return GoldenFiles.facts(file_name)


## The retail fact [param retail] for [param field] of [param family], or the
## reviewed override recorded for [param asset] (a path under [code]assets/[/code]).
func expected(asset: String, family: String, field: String, retail: String) -> String:
	if not _overrides_read:
		_overrides_read = true
		for row: PackedStringArray in _read_overrides():
			_overrides["%s\t%s\t%s" % [row[0], row[1], row[2]]] = row[3]
	return _overrides.get("%s\t%s\t%s" % [asset, family, field], retail)


## Every file under [param folder] (a [code]res://[/code] path) whose name ends
## with [param suffix], recursively, sorted.
func files_under(folder: String, suffix: String) -> PackedStringArray:
	var found := PackedStringArray()
	_collect(folder, suffix, found)
	found.sort()
	return found


## SHA-256 of [param bytes] as lower-case hex.
func sha256_hex(bytes: PackedByteArray) -> String:
	return GoldenFiles.sha256_hex(bytes)


func _read_overrides() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for line: String in FileAccess.get_file_as_string(OVERRIDES).split("\n", false):
		if line.begins_with("#"):
			continue
		var row: PackedStringArray = line.split("\t")
		if row.size() >= 5 and not row[4].strip_edges().is_empty():
			rows.append(row)
	return rows


func _collect(folder: String, suffix: String, into: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for child: String in DirAccess.get_directories_at(folder):
		_collect(folder.path_join(child), suffix, into)
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(suffix):
			into.append(folder.path_join(file))
