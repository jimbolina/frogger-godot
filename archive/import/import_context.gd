class_name ImportContext
extends RefCounted
## Shared state and path conventions for one importer run.
##
## Steps read the retail data through [member data], write under
## [member assets_root] and report problems through [method report]. Every
## asset path convention lives here so steps and tests agree on it.

## The retail files, open for reading.
var data: GameData
## Where assets are written; the committed location is [code]res://assets[/code].
var assets_root: String = "res://assets"
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


## Records a problem; the run exits non-zero when any exists.
func report(message: String) -> void:
	problems.append(message)
	printerr("import: " + message)


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
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		report("cannot write %s" % path)
		return false
	file.store_buffer(bytes)
	file.close()
	written.append(path)
	return true


## Saves [param resource] at [param path], overwriting in place so its UID
## survives; binary [code].res[/code] files are compressed. Returns false and
## reports on failure.
func save_resource(resource: Resource, path: String) -> bool:
	ensure_dir(path.get_base_dir())
	var flags: int = ResourceSaver.FLAG_COMPRESS if path.ends_with(".res") else 0
	resource.take_over_path(path)
	var result: Error = ResourceSaver.save(resource, path, flags)
	if result != OK:
		report("cannot save %s (%s)" % [path, error_string(result)])
		return false
	written.append(path)
	return true


## The committed PNG for texture [param texture_id] (pixels are identical for
## every bank holding the id).
func texture_png_path(texture_id: int) -> String:
	return "%s/textures/images/t%04d.png" % [assets_root, texture_id]


## The bank resource for VLO [param bank_name] (the MWI display name without
## its extension, for example [code]GEN_VRAM[/code]).
func bank_resource_path(bank_name: String) -> String:
	return "%s/textures/banks/%s.tres" % [assets_root, bank_name]


## The folder of a baked texture-page set named [param set_name].
func page_set_dir(set_name: String) -> String:
	return "%s/textures/pages/%s" % [assets_root, set_name]


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


## The WAV of sample [param index] in sound bank [param bank_name].
func sfx_path(bank_name: String, index: int, sample_name: String) -> String:
	var label: String = sample_name if not sample_name.is_empty() else "sample"
	return "%s/audio/sfx/%s/%03d_%s.wav" % [assets_root, bank_name, index, label]


## The sound bank resource for [param bank_name].
func sound_bank_path(bank_name: String) -> String:
	return "%s/audio/sfx/%s.tres" % [assets_root, bank_name]


## The Ogg Vorbis file for CD track [param track].
func music_path(track: int) -> String:
	return "%s/audio/music/track_%02d.ogg" % [assets_root, track]


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
