extends RetailTest
## The runtime import, run once through [AssetImporterFactory] from
## FROGGER_DATA_DIR into a scratch user:// root,
## writes what the editor import of the committed assets/ holds, with no PNG,
## WAV or import file. The committed assets are the oracle: Godot's editor
## import produced them from the same retail files
## (tests/golden/specs/imported-assets.md#runtime-import).

const ROOT_PARENT: String = "user://runtime_import_golden"
const TARGET: String = ROOT_PARENT + "/assets"
const COMMITTED: String = "res://assets"
## The folders and files the importer owns, compared resource by resource.
const RECORD_FOLDERS: PackedStringArray = ["tables", "demos", "maps", "textures/banks", "audio/sfx", "models",
	"materials"]
const MAX_DIFFERENCES: int = 20
const MusicStep := preload("res://archive/import/steps/music_step.gd")

var _importer: AssetImporter
var _problems: PackedStringArray = PackedStringArray()
var _fractions: Array[float] = []
var _labels: PackedStringArray = PackedStringArray()
var _milliseconds: int = 0
var _disc: String = ""


func before_all() -> void:
	RuntimeImport.remove_tree(ROOT_PARENT)
	_disc = OS.get_environment(DiscAudio.ENVIRONMENT_VARIABLE)
	_importer = AssetImporterFactory.create()
	var started: int = Time.get_ticks_msec()
	_problems = _importer.run(OS.get_environment(GameDataLocator.ENV_VAR), _disc, TARGET, _on_progress, Callable())
	_milliseconds = Time.get_ticks_msec() - started
	gut.p("runtime import: %.1f s, %s, %d problems" % [_milliseconds / 1000.0,
		"with music" if not _disc.is_empty() else "without music", _problems.size()])


func after_all() -> void:
	RuntimeImport.remove_tree(ROOT_PARENT)


func _on_progress(fraction: float, label: String) -> void:
	_fractions.append(fraction)
	_labels.append(label)


func test_the_import_succeeds_with_progress() -> void:
	assert_true(_importer is RuntimeImport, "the factory gives the runtime adapter")
	assert_eq(_problems, PackedStringArray())
	assert_true(FileAccess.file_exists(TARGET.path_join("catalog.tres")))
	assert_false(DirAccess.dir_exists_absolute(TARGET + RuntimeImport.STAGING_SUFFIX))
	assert_false(DirAccess.dir_exists_absolute(TARGET + RuntimeImport.RETIRED_SUFFIX))
	assert_gt(_fractions.size(), 100)
	var rising: bool = true
	for at: int in range(1, _fractions.size()):
		rising = rising and _fractions[at] >= _fractions[at - 1]
	assert_true(rising, "progress never goes back")
	assert_eq(_fractions[-1] if not _fractions.is_empty() else 0.0, 1.0)
	assert_true(_labels.has("Converting models"))
	var music_noted: bool = false
	for note: String in _importer.notes:
		music_noted = music_noted or note.contains("no music")
	assert_eq(music_noted, _disc.is_empty(), "a run without a disc notes that it has no music")


func test_detection_names_the_build_and_fingerprint() -> void:
	var detection: AssetImporter.Detection = _importer.detect(OS.get_environment(GameDataLocator.ENV_VAR))
	assert_true(detection.is_ok(), detection.error)
	assert_eq(detection.build, AssetImporter.SUPPORTED_BUILD)
	assert_eq(detection.fingerprint.length(), RuntimeImport.KEY_LENGTH)
	assert_true(detection.fingerprint.is_valid_hex_number())
	assert_string_contains(detection.summary, AssetImporter.SUPPORTED_BUILD)
	assert_eq(AssetImporter.root_for(detection.fingerprint), "user://assets/" + detection.fingerprint)
	var missing: AssetImporter.Detection = _importer.detect(ROOT_PARENT.path_join("no_such_folder"))
	assert_false(missing.is_ok())
	assert_string_contains(missing.error, "no folder")


func test_a_cancelled_import_leaves_no_folder() -> void:
	var target: String = ROOT_PARENT.path_join("cancelled")
	var problems: PackedStringArray = AssetImporterFactory.create().run(OS.get_environment(GameDataLocator.ENV_VAR),
		"", target, Callable(), func() -> bool: return true)
	assert_eq(problems, PackedStringArray(["the import was cancelled"]))
	assert_false(DirAccess.dir_exists_absolute(target))
	assert_false(DirAccess.dir_exists_absolute(target + RuntimeImport.STAGING_SUFFIX))


func test_nothing_needs_the_editor_import() -> void:
	var editor_files := PackedStringArray()
	for path: String in _files(TARGET):
		if path.get_extension() in ["png", "wav", "ogg", "import"]:
			editor_files.append(path)
	assert_eq(editor_files, PackedStringArray())


func test_the_same_files_are_written() -> void:
	var folders: PackedStringArray = RECORD_FOLDERS.duplicate()
	folders.append("textures/images")
	for folder: String in folders:
		var committed: PackedStringArray = _stems(COMMITTED, folder)
		var runtime: PackedStringArray = _stems(TARGET, folder)
		assert_gt(committed.size(), 0, folder)
		assert_eq(runtime, committed, folder)


func test_records_are_resource_equal() -> void:
	var differences := PackedStringArray()
	var compared: int = 0
	var paths := PackedStringArray(["catalog.tres"])
	for folder: String in RECORD_FOLDERS:
		for path: String in _files(COMMITTED.path_join(folder)):
			if path.get_extension() in ["tres", "res", "tscn"]:
				paths.append(path.trim_prefix(COMMITTED + "/"))
	for relative: String in paths:
		var committed: Resource = load(COMMITTED.path_join(relative))
		var runtime_path: String = TARGET.path_join(relative)
		var runtime: Resource = load(runtime_path) if ResourceLoader.exists(runtime_path) else null
		if runtime == null:
			differences.append("%s does not load from the runtime root" % relative)
			continue
		_compare_properties(committed, runtime, relative, differences, {})
		compared += 1
		if differences.size() >= MAX_DIFFERENCES:
			break
	assert_eq(differences, PackedStringArray())
	assert_gt(compared, 2000)


func test_every_texture_is_pixel_equal() -> void:
	var failures := PackedStringArray()
	var images: PackedStringArray = _files(COMMITTED.path_join("textures/images"))
	var compared: int = 0
	for path: String in images:
		if path.get_extension() != "png":
			continue
		var committed: Image = (load(path) as Texture2D).get_image()
		var runtime_path: String = TARGET.path_join(path.trim_prefix(COMMITTED + "/").get_basename() + ".res")
		var texture: Texture2D = load(runtime_path) as Texture2D if ResourceLoader.exists(runtime_path) else null
		var runtime: Image = texture.get_image() if texture != null else null
		compared += 1
		if runtime == null:
			failures.append("%s has no runtime texture" % path)
		elif not (texture is PortableCompressedTexture2D) or runtime.get_size() != committed.get_size() \
				or runtime.get_format() != committed.get_format() or runtime.has_mipmaps() != committed.has_mipmaps() \
				or runtime.get_data() != committed.get_data():
			failures.append("%s differs from %s" % [runtime_path, path])
		if failures.size() >= MAX_DIFFERENCES:
			break
	assert_eq(failures, PackedStringArray())
	assert_eq(compared, 1858)


func test_every_sound_effect_is_pcm_equal() -> void:
	var failures := PackedStringArray()
	var compared: int = 0
	for path: String in _files(COMMITTED.path_join("audio/sfx")):
		if path.get_extension() != "wav":
			continue
		var committed: AudioStreamWAV = load(path) as AudioStreamWAV
		var runtime_path: String = TARGET.path_join(path.trim_prefix(COMMITTED + "/").get_basename() + ".res")
		var runtime: AudioStreamWAV = load(runtime_path) as AudioStreamWAV if ResourceLoader.exists(runtime_path) else null
		compared += 1
		if runtime == null:
			failures.append("%s has no runtime sound" % path)
		elif runtime.format != committed.format or runtime.mix_rate != committed.mix_rate \
				or runtime.stereo != committed.stereo or runtime.loop_mode != committed.loop_mode \
				or runtime.loop_begin != committed.loop_begin or runtime.loop_end != committed.loop_end \
				or runtime.data != committed.data:
			failures.append("%s differs from %s" % [runtime_path, path])
	assert_eq(failures, PackedStringArray())
	assert_eq(compared, 174)


func test_the_root_opens_as_the_game_catalog() -> void:
	var catalog: ImportedAssets = ImportedAssets.open(TARGET)
	assert_eq(catalog.error, "")
	var entry: MwiEntry = catalog.find_resource("ORG1.MAP")
	var map_id: int = entry.index if entry != null else -1
	var problems := PackedStringArray()
	assert_not_null(catalog.read_map(map_id, problems), "ORG1 loads from the runtime root")
	assert_eq(problems, PackedStringArray())
	catalog.close()


func test_music_follows_the_disc() -> void:
	var folder: String = TARGET.path_join("audio/music")
	if _disc.is_empty():
		assert_false(DirAccess.dir_exists_absolute(folder), "no disc, no music")
		return
	var failures := PackedStringArray()
	var rows: Array[PackedStringArray] = []
	for line: String in FileAccess.get_file_as_string(MusicStep.FACTS).split("\n", false):
		if not line.begins_with("#"):
			rows.append(line.split("\t"))
	assert_eq(rows.size(), 31)
	for row: PackedStringArray in rows:
		var path: String = folder.path_join("track_%02d.res" % int(row[0]))
		var stream: AudioStreamWAV = load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
		if stream == null:
			failures.append("%s does not load" % path)
		elif stream.format != AudioStreamWAV.FORMAT_16_BITS or not stream.stereo or stream.mix_rate != 44100 \
				or stream.loop_mode != AudioStreamWAV.LOOP_DISABLED or stream.data.size() != int(row[4]) * 4 \
				or GoldenFiles.sha256_hex(stream.data) != row[6]:
			failures.append("%s differs from the disc facts" % path)
	assert_eq(failures, PackedStringArray())


func _compare_values(expected: Variant, actual: Variant, label: String, into: PackedStringArray,
		seen: Dictionary[String, bool]) -> void:
	if into.size() >= MAX_DIFFERENCES:
		return
	if expected is Resource or actual is Resource:
		_compare_resources(expected, actual, label, into, seen)
		return
	if typeof(expected) != typeof(actual):
		into.append("%s: %s, not %s" % [label, type_string(typeof(actual)), type_string(typeof(expected))])
		return
	match typeof(expected):
		TYPE_ARRAY:
			var want: Array = expected
			var got: Array = actual
			if want.size() != got.size():
				into.append("%s: %d items, not %d" % [label, got.size(), want.size()])
				return
			for at: int in want.size():
				_compare_values(want[at], got[at], "%s[%d]" % [label, at], into, seen)
		TYPE_DICTIONARY:
			var want: Dictionary = expected
			var got: Dictionary = actual
			if want.keys() != got.keys():
				into.append("%s: keys differ" % label)
				return
			for key: Variant in want:
				_compare_values(want[key], got[key], "%s[%s]" % [label, str(key)], into, seen)
		TYPE_STRING, TYPE_STRING_NAME:
			if _normalized(str(expected)) != _normalized(str(actual)):
				into.append("%s: %s, not %s" % [label, str(actual), str(expected)])
		_:
			if expected != actual:
				into.append("%s differs" % label)


func _compare_resources(expected: Variant, actual: Variant, label: String, into: PackedStringArray,
		seen: Dictionary[String, bool]) -> void:
	if not (expected is Resource and actual is Resource):
		into.append("%s: one side is not a resource" % label)
		return
	var want: Resource = expected
	var got: Resource = actual
	if _is_external(want) or _is_external(got):
		if _normalized(want.resource_path) != _normalized(got.resource_path):
			into.append("%s: refers to %s, not %s" % [label, got.resource_path, want.resource_path])
		return
	_compare_properties(want, got, label, into, seen)


func _compare_properties(want: Resource, got: Resource, label: String, into: PackedStringArray,
		seen: Dictionary[String, bool]) -> void:
	var key: String = "%d:%d" % [want.get_instance_id(), got.get_instance_id()]
	if seen.has(key):
		return
	seen[key] = true
	if want.get_class() != got.get_class():
		into.append("%s: %s, not %s" % [label, got.get_class(), want.get_class()])
		return
	for property: Dictionary in want.get_property_list():
		var usage: int = property["usage"]
		var property_name: StringName = property["name"]
		if (usage & PROPERTY_USAGE_STORAGE) == 0 or property_name == &"resource_path":
			continue
		_compare_values(want.get(property_name), got.get(property_name), "%s.%s" % [label, property_name], into, seen)


func _is_external(resource: Resource) -> bool:
	return not resource.resource_path.is_empty() and not resource.resource_path.contains("::")


func _normalized(text: String) -> String:
	for root: String in [COMMITTED, TARGET]:
		if text.begins_with(root + "/"):
			return "<root>/" + text.substr(root.length() + 1).get_basename()
	return text


func _stems(root: String, folder: String) -> PackedStringArray:
	var stems := PackedStringArray()
	for path: String in _files(root.path_join(folder)):
		if not path.get_extension() in ["import", "uid"]:
			stems.append(path.trim_prefix(root + "/").get_basename())
	stems.sort()
	return stems


func _files(folder: String) -> PackedStringArray:
	var found := PackedStringArray()
	if not DirAccess.dir_exists_absolute(folder):
		return found
	for child: String in DirAccess.get_directories_at(folder):
		found.append_array(_files(folder.path_join(child)))
	for file_name: String in DirAccess.get_files_at(folder):
		found.append(folder.path_join(file_name))
	return found
