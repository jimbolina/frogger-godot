class_name AssetTest
extends GutTest
## Base of the import goldens under [code]tests/imported/golden/assets/[/code]:
## opens the local import as an [ImportedAssets] catalog (once per run, through
## [AssetTestCache]) and reads the retail facts they are compared with.

## Where the imported assets live.
const ASSETS: String = AssetTestCache.ASSETS
## The environment variable naming the folder [code]tools/run_tests[/code]
## writes the Python golden generators' output into from the imported assets.
const GENERATED_VARIABLE: String = "FROGGER_GENERATED_DIR"
## Where the facts about locally derived assets live.
const IMPORTED_DIR: String = "res://tests/golden/imported"


## The local import, opened once and shared by every asset test.
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


## Every file under [param folder] (a [code]res://[/code] path) whose name ends
## with [param suffix], recursively, sorted.
func files_under(folder: String, suffix: String) -> PackedStringArray:
	return GoldenFiles.files_under(folder, suffix)


## The folder [param name] of the generators' output under
## [constant GENERATED_VARIABLE], or "" with a failed test when it is unset.
func generated_folder(name: String) -> String:
	var folder: String = OS.get_environment(GENERATED_VARIABLE)
	if folder.is_empty():
		fail_test("%s is not set; run the suite through tools/run_tests" % GENERATED_VARIABLE)
		return ""
	return folder.path_join(name)


## SHA-256 of [param bytes] as lower-case hex.
func sha256_hex(bytes: PackedByteArray) -> String:
	return GoldenFiles.sha256_hex(bytes)

