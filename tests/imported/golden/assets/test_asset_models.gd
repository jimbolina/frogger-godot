extends AssetTest
## The imported models match the retail facts. Every part of
## model_meshes.tsv is compared with its part mesh in the model's
## [code]mesh.res[/code], and again in the options page's copy when the model
## has one: surfaces, triangles, cels and the order-free digests of positions
## (whole game units), colours (bytes) and texture pixels. Every model's
## [code]model.res[/code] and [code]model.tscn[/code] hold the parts
## mof_parts.tsv lists, and every animated model has its preview animations.

const MODELS: String = "res://assets/models"
const OPTIONS: String = "res://assets/models/options"

var _mesh_rows: Array[PackedStringArray]
var _part_counts: Dictionary[String, int] = {}
var _names: Dictionary[int, String] = {}


func before_all() -> void:
	_mesh_rows = fact_rows("model_meshes.tsv")
	for row: PackedStringArray in _mesh_rows:
		_names[int(row[0])] = row[1].get_basename()
	for row: PackedStringArray in fact_rows("mof_parts.tsv"):
		var key: String = "%s/%s" % [row[0], row[1]]
		_part_counts[key] = _part_counts.get(key, 0) + 1


func test_part_meshes_match_the_facts() -> void:
	var mismatches := PackedStringArray()
	var options: Dictionary[String, bool] = {}
	for row: PackedStringArray in _mesh_rows:
		var model_name: String = row[1].get_basename()
		_check_part(MODELS.path_join(model_name), row, mismatches)
		if DirAccess.dir_exists_absolute(OPTIONS.path_join(model_name)):
			options[model_name] = true
			_check_part(OPTIONS.path_join(model_name), row, mismatches)
	assert_eq(_mesh_rows.size(), int(fact_values("asset_census.txt")["model_parts"]), "every part has a fact row")
	assert_eq(options.size(), DirAccess.get_directories_at(OPTIONS).size(), "every options model has fact rows")
	assert_eq(mismatches.size(), 0, "\n".join(mismatches.slice(0, 12)))


func test_records_and_scenes_hold_every_part() -> void:
	var problems := PackedStringArray()
	var scenes: int = 0
	for resource_id: int in _names:
		var folder: String = MODELS.path_join(_names[resource_id])
		var file: MofFile = load(folder.path_join("model.res")) as MofFile
		if file == null:
			problems.append("%s: model.res does not load" % folder)
			continue
		for static_index: int in file.static_models.size():
			var want: int = _part_counts.get("%d/%d" % [resource_id, static_index], 0)
			if file.static_models[static_index].parts.size() != want:
				problems.append("%s static %d: %d parts, want %d" % [folder, static_index,
					file.static_models[static_index].parts.size(), want])
		var scene: PackedScene = load(folder.path_join("model.tscn")) as PackedScene
		if scene == null:
			problems.append("%s: model.tscn does not load" % folder)
			continue
		var root: Node = scene.instantiate()
		var want_parts: int = _part_counts.get("%d/0" % resource_id, 0)
		var parts: int = 0
		for child: Node in root.get_children():
			if child is MeshInstance3D and String(child.name).begins_with("Part_"):
				parts += 1
		if parts != want_parts or root.get_child_count() != want_parts:
			problems.append("%s: model.tscn has %d parts, want %d" % [folder, parts, want_parts])
		root.free()
		scenes += 1
	assert_eq(scenes, _names.size())
	assert_eq(problems.size(), 0, "\n".join(problems.slice(0, 12)))


func test_animated_models_have_preview_animations() -> void:
	var previews: int = 0
	var problems := PackedStringArray()
	for path: String in files_under(MODELS, "preview.res"):
		if path.begins_with(OPTIONS + "/"):
			continue
		var library: AnimationLibrary = load(path) as AnimationLibrary
		var file: MofFile = load(path.get_base_dir().path_join("model.res")) as MofFile
		if library == null or file == null or file.animated == null or library.get_animation_list().is_empty():
			problems.append("%s: no animations for an animated model" % path)
			continue
		var parts: int = file.static_models[0].parts.size()
		for animation_name: StringName in library.get_animation_list():
			if library.get_animation(animation_name).get_track_count() != parts:
				problems.append("%s %s: not one track per part" % [path, animation_name])
		previews += 1
	assert_eq(previews, int(fact_values("asset_census.txt")["models_animated"]))
	assert_eq(problems.size(), 0, "\n".join(problems.slice(0, 12)))


func test_the_imported_catalog_serves_the_committed_meshes() -> void:
	var assets: ImportedAssets = catalog()
	assert_eq(assets.error, "")
	var frog: MwiEntry = assets.find_resource("GEN_FROG.XAR")
	var entry_frog: MwiEntry = assets.find_resource(OptionsModels.ENTRY_FROG_NAME)
	assert_not_null(frog)
	assert_not_null(entry_frog)
	var mesh: ModelMesh = ModelMeshLibrary.mesh_for(assets, frog.index, TextureLibrary.new(), null)
	assert_same(mesh, load(MODELS.path_join("GEN_FROG/mesh.res")))
	assert_same(ModelMeshLibrary.mesh_for(assets, entry_frog.index, TextureLibrary.new(), null, "options"),
		load(OPTIONS.path_join("GENM_FROG/mesh.res")))
	var instance := AnimatedModelInstance.new()
	add_child_autofree(instance)
	instance.setup(mesh, ModelAnimationPlayer.new(assets.read_model(frog.index)))
	assert_eq(instance.part_nodes.size(), mesh.part_meshes.size())
	assert_eq(instance.part_nodes[0].mesh, mesh.part_meshes[0])


func _check_part(folder: String, row: PackedStringArray, mismatches: PackedStringArray) -> void:
	var mesh: ModelMesh = load(folder.path_join("mesh.res")) as ModelMesh if ResourceLoader.exists(folder.path_join("mesh.res")) else null
	var file: MofFile = load(folder.path_join("model.res")) as MofFile if ResourceLoader.exists(folder.path_join("model.res")) else null
	if mesh == null or file == null:
		mismatches.append("%s: mesh.res or model.res does not load" % folder)
		return
	var part_index: int = int(row[3])
	var part: ArrayMesh = mesh.part_meshes[part_index] if part_index < mesh.part_meshes.size() else null
	var cels: int = part.get_blend_shape_count() + 1 if part != null else file.static_models[int(row[2])].parts[part_index].partcels.size()
	if cels > 1 and part != null:
		var morph: ModelMorphMesh = mesh.morph_meshes[part_index] if part_index < mesh.morph_meshes.size() else null
		var oversized: bool = "\n".join(mesh.diagnostics).contains("part %d cel atlas" % part_index)
		if not oversized and (morph == null or morph.textures.size() != part.get_surface_count()
				or morph.mesh.get_surface_count() != part.get_surface_count() or morph.textures.has(null)):
			mismatches.append("%s part %d: cel atlases do not load" % [folder, part_index])
	var got: PackedStringArray = _part_facts(part)
	got.insert(2, str(cels))
	var fields: PackedStringArray = ["surfaces", "triangles", "cels", "positions_sha256", "colours_sha256", "uvs_sha256"]
	var columns: PackedInt32Array = [4, 5, 6, 8, 9, 10]
	for at: int in fields.size():
		var want: String = row[columns[at]]
		if got[at] != want:
			mismatches.append("%s part %d %s: %s, want %s" % [folder, part_index, fields[at], got[at], want])


func _part_facts(part: ArrayMesh) -> PackedStringArray:
	var positions := PackedStringArray()
	var colours := PackedStringArray()
	var uvs := PackedStringArray()
	var triangles: int = 0
	var surfaces: int = part.get_surface_count() if part != null else 0
	for surface: int in surfaces:
		var arrays: Array = part.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		triangles += vertices.size() / 3
		var position_values := PackedInt64Array()
		for vertex: Vector3 in vertices:
			var game: Vector3i = GameSpace.to_game(vertex)
			position_values.append_array([game.x, game.y, game.z])
		positions.append(_digest(position_values))
		var colour_values := PackedInt64Array()
		for color: Color in colors:
			colour_values.append_array([color.r8, color.g8, color.b8, color.a8])
		colours.append(_digest(colour_values))
		if arrays[Mesh.ARRAY_TEX_UV] != null:
			var coordinates: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			uvs.append(_digest(_pixels(coordinates, part.surface_get_material(surface) as ShaderMaterial)))
	return PackedStringArray([str(surfaces), str(triangles), _sorted_digest(positions),
		_sorted_digest(colours), _sorted_digest(uvs)])


func _pixels(coordinates: PackedVector2Array, material: ShaderMaterial) -> PackedInt64Array:
	var values := PackedInt64Array()
	var image: Variant = material.get_shader_parameter("image") if material != null else null
	if not image is Texture2D:
		return values
	var texture: Texture2D = image
	var size: Vector2 = texture.get_size()
	var scale_value: Variant = material.get_shader_parameter("uv_scale")
	var offset_value: Variant = material.get_shader_parameter("uv_offset")
	var scale: Vector2 = scale_value if scale_value is Vector2 else Vector2.ONE
	var offset: Vector2 = offset_value if offset_value is Vector2 else Vector2.ZERO
	for coordinate: Vector2 in coordinates:
		var pixel: Vector2 = (coordinate * scale + offset) * size
		values.append_array([roundi(pixel.x), roundi(pixel.y)])
	return values


func _digest(values: PackedInt64Array) -> String:
	return "-" if values.is_empty() else GoldenFiles.list_digest(values)


func _sorted_digest(digests: PackedStringArray) -> String:
	if digests.is_empty():
		return "-"
	var sorted: PackedStringArray = digests.duplicate()
	sorted.sort()
	return sha256_hex(",".join(sorted).to_ascii_buffer())
