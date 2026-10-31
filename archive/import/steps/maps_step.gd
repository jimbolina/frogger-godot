extends ImportStep
## Saves every map and both sky-land tile files as compressed binary resources.
##
## Each regular map is the [MapFile] record [GameData] decodes, and each sky-land
## file its [SkyLandFile], written at [method ImportContext.map_path] under the
## MWI display name. Sub-resources get scene-unique ids numbered in traversal
## order so a rerun writes identical bytes. Every saved file is reloaded,
## bypassing the cache, and its section counts and storage columns are compared
## with the decoded record.

const SKY_LAND_FILES: Dictionary[String, bool] = {"SKY_LAND.MAP": false, "SKY_LAND_WIN95.MAP": true}


func step_name() -> String:
	return "maps"


func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_RESOURCES])


func run(context: ImportContext, phase: String) -> void:
	if phase != PHASE_RESOURCES:
		return
	for entry: MwiEntry in context.data.map_entries():
		var problems := PackedStringArray()
		var map: MapFile = context.data.read_map(entry.index, problems)
		if map == null:
			context.report("map %s: %s" % [entry.display_name(), "; ".join(problems)])
			continue
		map.resource_name = entry.display_name()
		_save_checked(context, map, context.map_path(context.entry_name(entry.index)))
	for file_name: String in SKY_LAND_FILES:
		var found: MwiEntry = context.data.find_resource(file_name)
		if found == null:
			context.report("no sky-land file %s" % file_name)
			continue
		var problems := PackedStringArray()
		var sky: SkyLandFile = context.data.read_sky_land(SKY_LAND_FILES[file_name], problems)
		if sky == null:
			context.report("sky land %s: %s" % [file_name, "; ".join(problems)])
			continue
		sky.resource_name = file_name
		_save_checked(context, sky, context.map_path(context.entry_name(found.index)))


func _save_checked(context: ImportContext, record: Resource, path: String) -> void:
	ImportContext.number_sub_resources(record)
	if not context.save_resource(record, path):
		return
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null:
		context.report("%s does not load back" % path)
		return
	var want: Dictionary[String, Variant] = _census(record)
	var got: Dictionary[String, Variant] = _census(loaded)
	for key: String in want:
		if not got.has(key) or got[key] != want[key]:
			context.report("%s reloads with a different %s" % [path, key])
func _census(record: Resource) -> Dictionary[String, Variant]:
	var result: Dictionary[String, Variant] = {}
	if record is SkyLandFile:
		var sky: SkyLandFile = record
		result["dimensions"] = sky.dimensions
		result["packed tiles"] = sky.packed_tiles
		result["texture ids"] = sky.texture_ids
		result["rotations"] = sky.rotations
		return result
	var map: MapFile = record
	result["size"] = map.size
	result["vertices"] = map.vertices.size()
	result["polygons"] = map.polygons.size()
	result["polygon records"] = map.polygon_records
	result["polygon words"] = map.polygon_words
	result["polygon colours"] = map.polygon_colors
	result["polygon uvs"] = map.polygon_uvs
	result["groups"] = map.groups.size()
	result["grid stacks"] = map.grid_stacks.size()
	result["grid squares"] = map.grid_squares.size()
	result["grid stack records"] = map.grid_stack_records
	result["grid square records"] = map.grid_square_records
	result["paths"] = map.paths.size()
	result["entities"] = map.entities.size()
	result["forms"] = map.forms.size()
	result["zones"] = map.zones.size()
	result["lights"] = map.lights.size()
	result["animations"] = map.animations.size()
	result["packets"] = map.packets.keys()
	return result
