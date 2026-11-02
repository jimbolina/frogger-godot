class_name FrogLordModFixture
extends RefCounted
## A synthetic FrogLord save of the retail install, written for the round-trip test.
##
## [method write] opens the retail files, applies the edit specification with
## [FrogLordExePatcher] and writes FrogLord's modded executable, archive and
## standalone index with [FrogLordMwdWriter].

## Why the fixture could not be written, or "".
var error: String = ""
## The modded executable written.
var exe_path: String = ""
## The modded archive written.
var mwd_path: String = ""
## The standalone index written.
var mwi_path: String = ""
## Each edit as applied, in the golden [code]edit[/code] schema ([member FrogLordExePatcher.edits]).
var edits: Array[PackedStringArray] = []


## Writes the save of the retail files in [param retail_dir], edited as
## [param spec_path] specifies, into [param out_dir] (created with its parents).
static func write(retail_dir: String, out_dir: String, spec_path: String) -> FrogLordModFixture:
	var fixture := FrogLordModFixture.new()
	var spec: FrogLordEditSpec = FrogLordEditSpec.read(spec_path)
	if not spec.error.is_empty():
		fixture.error = "edit specification: %s" % spec.error
		return fixture
	var source := RetailDirSource.new(retail_dir)
	if not source.is_complete():
		fixture.error = "%s lacks %s" % [retail_dir, ", ".join(source.missing_files())]
		return fixture
	var library := FrogLordConfigLibrary.new()
	var detection: GameVersionDetector.Result = GameVersionDetector.new(library).detect(source.get_exe_bytes())
	if not detection.is_ok():
		fixture.error = detection.error
		return fixture
	var data: GameData = GameData.open(source, detection.version, library)
	if not data.is_valid():
		fixture.error = data.error
		return fixture
	fixture.error = fixture._write(data, spec, out_dir)
	data.close()
	return fixture


func _write(data: GameData, spec: FrogLordEditSpec, out_dir: String) -> String:
	var patcher: FrogLordExePatcher = FrogLordExePatcher.apply(data, spec)
	if not patcher.error.is_empty():
		return patcher.error
	edits = patcher.edits
	var made: Error = DirAccess.make_dir_recursive_absolute(out_dir)
	if made != OK:
		return "cannot create %s (%s)" % [out_dir, error_string(made)]
	var writer: FrogLordMwdWriter = FrogLordMwdWriter.write(data, patcher.exe_bytes, patcher.files, out_dir)
	if not writer.error.is_empty():
		return writer.error
	exe_path = out_dir.path_join(FrogLordModSource.EXE_NAME)
	mwd_path = out_dir.path_join(FrogLordModSource.MWD_NAME)
	mwi_path = out_dir.path_join(FrogLordModSource.MWI_NAME)
	return ""
