class_name ImportContext
extends RefCounted
## Shared state and path conventions for one importer run.
##
## Steps read the retail data through [member data], write under
## [member assets_root], report problems through [method report] and remarks
## through [method note]. Every asset path convention lives here so steps and
## tests agree on it. [member touched] lists every file the run wrote or found
## unchanged; [method keep_record] and [method restore_record] carry it, with
## [member complete_phases], between the phases of one run through the
## scratch folder.
##
## A [member runtime] run needs no editor import: textures, sound effects and
## music are written as binary resources Godot loads directly, and every saved
## resource names its external resources by their [member published_root]
## path, so the folder can be written under one name and renamed to that root.

## The scratch file holding the record of earlier phases.
const RECORD_FILE: String = "import_record.json"

## The retail files, open for reading.
var data: GameData
## Where assets are written; the committed location is [code]res://assets[/code].
var assets_root: String = "res://assets"
## A complete asset root whose files the catalog step records for every
## resource this run did not write, so an overlay index is complete; empty
## when [member assets_root] is complete on its own.
var fallback_root: String = ""
## An absolute folder outside the repository for intermediate files such as
## decoded music WAVs; empty when the run has no scratch folder.
var scratch: String = ""
## The disc image path for the music step; empty when none was supplied.
var disc: String = ""
## Re-encode music tracks even when their Ogg file exists.
var force_music: bool = false
## Texture banks decoded by the textures step, by bank name, for later steps.
var banks: Dictionary[String, VloFile] = {}
## Problems reported so far; a non-empty list fails the run.
var problems: PackedStringArray = PackedStringArray()
## Files written or rewritten during this run.
var written: PackedStringArray = PackedStringArray()
## Files whose content was already identical.
var unchanged: int = 0
## Every file written or found unchanged during this run, earlier phases
## included once [method restore_record] has run.
var touched: PackedStringArray = PackedStringArray()
## The phases in which every step ran, so [member touched] lists all their output.
var complete_phases: PackedStringArray = PackedStringArray()
## Remarks that do not fail the run.
var notes: PackedStringArray = PackedStringArray()
## Write textures as [PortableCompressedTexture2D], sound effects and music as
## [AudioStreamWAV] binary resources instead of the PNG and WAV files Godot's
## editor import turns into resources, so one pass writes a complete root.
var runtime: bool = false
## Where [member assets_root] will live once the run is over; saved
## references and the index name files under it. Empty when the run writes
## in place.
var published_root: String = ""
## Called as [code]on_progress.call(done, total)[/code] by long steps as they
## work through their items; unset when nobody follows the run.
var on_progress: Callable = Callable()
## Returns true when the run should stop; steps check it between items.
var cancelled: Callable = Callable()
var _loaded: Dictionary[String, Resource] = {}


## Records a problem; the run exits non-zero when any exists.
func report(message: String) -> void:
	problems.append(message)
	printerr("import: " + message)


## Records a remark that does not fail the run.
func note(message: String) -> void:
	notes.append(message)
	print("import: note " + message)


## Merges the record [method keep_record] left in the scratch folder into
## [member touched] and [member complete_phases]; does nothing without a
## scratch folder or a record.
func restore_record() -> void:
	if scratch.is_empty():
		return
	var path: String = scratch.path_join(RECORD_FILE)
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		report("cannot read the run record %s" % path)
		return
	var record: Dictionary = parsed
	touched = _merged(touched, record.get("touched", []))
	complete_phases = _merged(complete_phases, record.get("complete_phases", []))


static func _merged(into: PackedStringArray, listed: Variant) -> PackedStringArray:
	var merged: PackedStringArray = into
	var present: Dictionary[String, bool] = {}
	for text: String in merged:
		present[text] = true
	if listed is Array:
		var items: Array = listed
		for item: Variant in items:
			var text: String = str(item)
			if not present.has(text):
				present[text] = true
				merged.append(text)
	return merged


## Saves [member touched] and [member complete_phases] in the scratch folder
## for the run's next phase; does nothing without a scratch folder.
func keep_record() -> void:
	if scratch.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(scratch)
	var file: FileAccess = FileAccess.open(scratch.path_join(RECORD_FILE), FileAccess.WRITE)
	if file == null:
		report("cannot write the run record in %s" % scratch)
		return
	file.store_string(JSON.stringify({"touched": Array(touched), "complete_phases": Array(complete_phases)}))
	file.close()


## True when [member cancelled] asks the run to stop.
func is_cancelled() -> bool:
	if not cancelled.is_valid():
		return false
	var answer: Variant = cancelled.call()
	return answer is bool and answer


## Tells [member on_progress] that [param done] of [param total] items of the
## current step are finished.
func advance(done: int, total: int) -> void:
	if on_progress.is_valid():
		on_progress.call(done, total)


## [param path], a file under [member assets_root], as it will be named under
## [member published_root]; unchanged when the run writes in place.
func published_path(path: String) -> String:
	if published_root.is_empty():
		return path
	var relative: String = relative_to_assets(path)
	return published_root.path_join(relative) if not relative.is_empty() else path


## The resource at [param path], a file this run wrote under
## [member assets_root] (or Godot imported from one), named by its
## [method published_path] so that resources referring to it are saved with
## that path. Returns null when it does not load.
func load_written(path: String) -> Resource:
	if _loaded.has(path):
		return _loaded[path]
	if not ResourceLoader.exists(path):
		return null
	var resource: Resource = load(path)
	if resource == null:
		return null
	var published: String = published_path(path)
	if published != path:
		resource.take_over_path(published)
	_loaded[path] = resource
	return resource


## Creates [param path] (a [code]res://[/code] folder) and its parents.
func ensure_dir(path: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		DirAccess.make_dir_recursive_absolute(absolute)


## Writes [param bytes] to [param path] only when the content differs, so
## unchanged files keep their modification time and Git sees no change.
func write_if_changed(path: String, bytes: PackedByteArray) -> bool:
	ensure_dir(path.get_base_dir())
	if FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) == bytes:
		unchanged += 1
		touched.append(path)
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		report("cannot write %s" % path)
		return false
	file.store_buffer(bytes)
	file.close()
	written.append(path)
	touched.append(path)
	return true


## Saves [param resource] at [param path], overwriting in place so its UID
## survives; binary [code].res[/code] files are compressed. The resource takes
## over its [method published_path], so later saves refer to it there.
## Returns false and reports on failure.
func save_resource(resource: Resource, path: String) -> bool:
	ensure_dir(path.get_base_dir())
	var flags: int = ResourceSaver.FLAG_COMPRESS if path.ends_with(".res") else 0
	resource.take_over_path(published_path(path))
	var result: Error = ResourceSaver.save(resource, path, flags)
	if result != OK:
		report("cannot save %s (%s)" % [path, error_string(result)])
		return false
	written.append(path)
	touched.append(path)
	return true


## The part of [param path] below [member assets_root], or "" when it lies
## elsewhere.
func relative_to_assets(path: String) -> String:
	var prefix: String = assets_root.trim_suffix("/") + "/"
	return path.substr(prefix.length()) if path.begins_with(prefix) else ""


## The image file for texture [param texture_id] (pixels are identical for
## every bank holding the id): a PNG, or a [PortableCompressedTexture2D]
## resource in a [member runtime] run.
func texture_image_path(texture_id: int) -> String:
	return "%s/textures/images/t%04d.%s" % [assets_root, texture_id, "res" if runtime else "png"]


## The bank resource for VLO [param bank_name] (the MWI display name without
## its extension, for example [code]GEN_VRAM[/code]).
func bank_resource_path(bank_name: String) -> String:
	return "%s/textures/banks/%s.tres" % [assets_root, bank_name]


## The folder holding model [param model_name]'s resources and scene.
func model_dir(model_name: String) -> String:
	return "%s/models/%s" % [assets_root, model_name]


## The shared material for texture [param texture_id] in blend mode
## [param blend], two-sided when [param two_sided].
func material_path(texture_id: int, blend: int, two_sided: bool) -> String:
	var suffix: String = "_2s" if two_sided else ""
	return "%s/materials/model/t%04d_b%d%s.tres" % [assets_root, texture_id, blend, suffix]


## The map resource for the MWI entry named [param map_name].
func map_path(map_name: String) -> String:
	return "%s/maps/%s.res" % [assets_root, map_name]


## The sound of sample [param index] in sound bank [param bank_name]: a WAV,
## or an [AudioStreamWAV] resource in a [member runtime] run.
func sfx_path(bank_name: String, index: int, sample_name: String) -> String:
	var label: String = sample_name if not sample_name.is_empty() else "sample"
	return "%s/audio/sfx/%s/%03d_%s.%s" % [assets_root, bank_name, index, label, "res" if runtime else "wav"]


## The sound bank resource for [param bank_name].
func sound_bank_path(bank_name: String) -> String:
	return "%s/audio/sfx/%s.tres" % [assets_root, bank_name]


## The music of CD track [param track]: an Ogg Vorbis file, or an
## [AudioStreamWAV] resource in a [member runtime] run.
func music_path(track: int) -> String:
	return "%s/audio/music/track_%02d.%s" % [assets_root, track, "res" if runtime else "ogg"]


## The scratch WAV decoded from the disc for CD track [param track].
func music_scratch_wav(track: int) -> String:
	return scratch.path_join("track_%02d.wav" % track)


## The demo resource for the MWI entry named [param demo_name].
func demo_path(demo_name: String) -> String:
	return "%s/demos/%s.tres" % [assets_root, demo_name]


## The table resource named [param table_name], for example
## [code]theme_book[/code].
func table_path(table_name: String) -> String:
	return "%s/tables/%s.tres" % [assets_root, table_name]


## The asset index.
func catalog_path() -> String:
	return "%s/catalog.tres" % assets_root


## Gives every sub-resource under [param root] a deterministic scene-unique
## id, [code]<Class>_<n>[/code] in walk order, so repeated saves are byte-identical.
static func number_sub_resources(root: Resource) -> void:
	var counter: Array[int] = [0]
	var visited: Dictionary[int, bool] = {}
	_number(root, counter, visited, true)


static func _number(resource: Resource, counter: Array[int], visited: Dictionary[int, bool], is_root: bool) -> void:
	if visited.has(resource.get_instance_id()):
		return
	visited[resource.get_instance_id()] = true
	if not is_root:
		var script: Script = resource.get_script()
		var label: String = script.get_global_name() if script != null else resource.get_class()
		resource.resource_scene_unique_id = "%s_%d" % [label, counter[0]]
		counter[0] += 1
	for property: Dictionary in resource.get_property_list():
		var usage: int = property["usage"]
		var property_name: StringName = property["name"]
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		_number_value(resource.get(property_name), counter, visited)


static func _number_value(value: Variant, counter: Array[int], visited: Dictionary[int, bool]) -> void:
	if value is Resource:
		var resource: Resource = value
		if resource.resource_path.is_empty() or resource.resource_path.contains("::"):
			_number(resource, counter, visited, false)
	elif value is Array:
		var items: Array = value
		for item: Variant in items:
			_number_value(item, counter, visited)
	elif value is Dictionary:
		var table: Dictionary = value
		for key: Variant in table:
			_number_value(key, counter, visited)
			_number_value(table[key], counter, visited)


## The display name of MWI entry [param resource_id] without its extension,
## used as a stable file name.
func entry_name(resource_id: int) -> String:
	var entry: MwiEntry = data.mwi.get_entry(resource_id)
	if entry == null:
		return "resource_%d" % resource_id
	return entry.display_name().get_basename()
