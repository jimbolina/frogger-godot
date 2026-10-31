class_name AssetTest
extends GutTest
## Base of the import goldens under [code]tests/golden/assets/[/code]: opens the
## committed assets as an [ImportedAssets] catalog (once per run, through
## [AssetTestCache]) and reads the retail facts and reviewed overrides they are
## compared with.

## Where the imported assets live.
const ASSETS: String = AssetTestCache.ASSETS
## Where the facts about locally derived assets live.
const IMPORTED_DIR: String = "res://tests/golden/imported"


## The committed assets, opened once and shared by every asset test.
func catalog() -> ImportedAssets:
	return AssetTestCache.catalog()


## Rows of the golden TSV [param file_name] (comment lines dropped).
func fact_rows(file_name: String) -> Array[PackedStringArray]:
	return GoldenFiles.rows(file_name)


## Rows of the derived-asset golden TSV [param file_name] under
## [code]tests/golden/imported/[/code] (comment lines dropped).
func imported_rows(file_name: String) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	for line: String in FileAccess.get_file_as_string(IMPORTED_DIR.path_join(file_name)).split("\n", false):
		if not line.begins_with("#"):
			result.append(line.split("\t"))
	return result


## The key=value facts of the golden text file [param file_name].
func fact_values(file_name: String) -> Dictionary[String, String]:
	return GoldenFiles.facts(file_name)


## The retail fact [param retail] for [param field] of [param family], or the
## reviewed override recorded for [param asset] (a path under [code]assets/[/code]).
func expected(asset: String, family: String, field: String, retail: String) -> String:
	return AssetTestCache.override(asset, family, field, retail)


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


func _collect(folder: String, suffix: String, into: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for child: String in DirAccess.get_directories_at(folder):
		_collect(folder.path_join(child), suffix, into)
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(suffix):
			into.append(folder.path_join(file))
