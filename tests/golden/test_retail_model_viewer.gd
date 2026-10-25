extends RetailTest
## Needs the retail files: the model viewer lists the WADs and shows chosen
## models with the triangle counts that follow from the golden facts, hides
## the parts FrogLord's settings hide, and every model of every high-poly WAD
## builds with all its textures found (but for one known exception).

const VIEWER_SCENE: String = "res://scenes/tools/model_viewer.tscn"

var _viewer: ModelViewer
var _data: GameData


func before_each() -> void:
	var scene: PackedScene = load(VIEWER_SCENE)
	_viewer = scene.instantiate() as ModelViewer
	_viewer.auto_open = false
	add_child_autofree(_viewer)
	_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))
	_viewer.open_data(_data, true)


func _golden_triangles() -> Dictionary[String, int]:
	var by_resource: Dictionary[int, int] = {}
	for row: PackedStringArray in GoldenFiles.rows("mof_parts.tsv"):
		if row[1] != "0":
			continue
		var counts: PackedStringArray = row[15].split(",")
		var triangles: int = 0
		for kind: int in counts.size():
			var corners: int = MofPolygonType.vertex_count(kind)
			if corners >= 3:
				triangles += counts[kind].to_int() * (corners - 2)
		by_resource[row[0].to_int()] = by_resource.get(row[0].to_int(), 0) + triangles
	var by_name: Dictionary[String, int] = {}
	for row: PackedStringArray in GoldenFiles.rows("mof_models.tsv"):
		by_name[row[1]] = by_resource.get(row[0].to_int(), 0)
	return by_name


func test_viewer_shows_models_by_name() -> void:
	var golden: Dictionary[String, int] = _golden_triangles()
	assert_gt(_viewer.wad_names().size(), 30)
	assert_true(_viewer.wad_names().has("THEME_GEN_HI.WAD"))
	assert_false(_viewer.wad_names().has("THEME_GEN.WAD"), "low-poly WADs are listed on request")
	for file_name: String in ["GEN_FROG.XAR", "GEN_CHECKPOINT_1.XMR", "GEN_CHECKPOINT_2.XMR", "JUN_LOG.XMR", "OPT_MUSIC.XMU"]:
		assert_eq(_viewer.load_model_by_name(file_name), golden[file_name], file_name)
		assert_eq(_viewer.current_mesh.missing_image_ids.size(), 0, "%s textures" % file_name)
	assert_eq(_viewer.load_model_by_name("NO_SUCH.XMR"), -1)
	assert_eq(_viewer.load_wad_model("THEME_GEN_HI.WAD", 999), -1)


func test_hidden_parts_follow_froglords_settings() -> void:
	assert_gt(_viewer.load_model_by_name("GEN_FROG.XAR"), 0)
	assert_eq(_viewer.part_node_count(), 16)
	assert_eq(_viewer.visible_part_count(), 15)


func test_low_poly_models_can_be_shown() -> void:
	assert_gt(_viewer.load_model_by_name("GEN_FROG_WIN95.XAR"), 0)
	assert_true(_viewer.wad_names().has("THEME_GEN.WAD"))


func test_representative_animations_reuse_render_resources() -> void:
	for file_name: String in ["GEN_FROG.XAR", "GEN_FROG_WIN95.XAR", "DES_VULTURE.XAR", "OPT_TURTLE.XMR", "GEN_CHECKPOINT_2.XMR"]:
		var build_started: int = Time.get_ticks_usec()
		assert_gt(_viewer.load_model_by_name(file_name), 0, file_name)
		var build_ms: float = float(Time.get_ticks_usec() - build_started) / 1000.0
		_viewer.set_playing(false)
		var instance: AnimatedModelInstance = _viewer.animated_instance
		var mesh_ids := PackedInt64Array()
		var material_ids := PackedInt64Array()
		for mesh: ArrayMesh in _viewer.current_mesh.part_meshes:
			mesh_ids.append(mesh.get_instance_id() if mesh != null else 0)
			if mesh != null:
				for surface: int in mesh.get_surface_count():
					material_ids.append(mesh.surface_get_material(surface).get_instance_id())
		var started: int = Time.get_ticks_usec()
		for smoothing: bool in [false, true]:
			instance.smoothing_enabled = smoothing
			for _tick: int in 180:
				instance.advance_tick()
				instance.render(0.5)
		var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
		var current_mesh_ids := PackedInt64Array()
		var current_material_ids := PackedInt64Array()
		for mesh: ArrayMesh in _viewer.current_mesh.part_meshes:
			current_mesh_ids.append(mesh.get_instance_id() if mesh != null else 0)
			if mesh != null:
				for surface: int in mesh.get_surface_count():
					current_material_ids.append(mesh.surface_get_material(surface).get_instance_id())
		assert_eq(current_mesh_ids, mesh_ids, file_name + " meshes stay allocated")
		assert_eq(current_material_ids, material_ids, file_name + " materials stay allocated")
		assert_eq(_viewer.player.tick, 360)
		print("TIMING: %s build %.2f ms; 360 tick/draw pairs %.2f ms (%.2f us each)" % [file_name, build_ms, elapsed_ms, elapsed_ms * 1000.0 / 360.0])


func test_every_high_poly_model_builds_with_its_textures() -> void:
	var problems := PackedStringArray()
	var missing := PackedStringArray()
	var built: int = 0
	var triangles: int = 0
	var started: int = Time.get_ticks_usec()
	var banks: Dictionary[int, VloFile] = {}
	var general_id: int = _data.theme_book_entry(FroggerIds.THEME_GENERAL).vlo_id()
	banks[general_id] = _data.read_texture_bank(general_id, problems)
	for wad_entry: MwiEntry in _data.mwi.wad_entries():
		if not _viewer.wad_names().has(wad_entry.display_name()):
			continue
		var bank_id: int = _data.texture_bank_for_wad(wad_entry.index)
		if bank_id > 0 and not banks.has(bank_id):
			banks[bank_id] = _data.read_texture_bank(bank_id, problems)
		var library := TextureLibrary.new()
		library.add_bank(banks[general_id], "general")
		var own: VloFile = banks[bank_id] if bank_id > 0 else null
		if own != null:
			library.add_bank(own, "own")
		var wad: WadFile = _data.read_wad(wad_entry.index)
		for position: int in wad.children.size():
			var model: MofFile = _data.read_wad_model(wad_entry.index, position, problems)
			if model == null:
				continue
			for model_index: int in model.static_models.size():
				var shape: MofStatic = model.static_models[model_index]
				var mesh: ModelMesh = ModelMeshBuilder.new(library, own).build(shape)
				var animated_mesh: ModelMesh = ModelMeshBuilder.new(library, own).build_animated(model, model_index)
				assert_eq(animated_mesh.triangle_count, mesh.triangle_count, "animated construction keeps polygon topology")
				assert_eq(animated_mesh.missing_image_ids, mesh.missing_image_ids, "animation frames resolve in the model's bank")
				built += 1
				triangles += mesh.triangle_count
				if not mesh.missing_image_ids.is_empty():
					missing.append("%s in %s: %s" % [_data.mwi.get_entry(wad.children[position].resource_id).display_name(),
						wad_entry.display_name(), str(mesh.missing_image_ids)])
	print("TIMING: built %d models (%d triangles) in %.0f ms" % [built, triangles, (Time.get_ticks_usec() - started) / 1000.0])
	assert_eq(problems.size(), 0, ", ".join(problems))
	var unexpected := PackedStringArray()
	for line: String in missing:
		if not (line.begins_with("JUN_PLINTH") and line.contains(" in THEME_JUNM.WAD: ")):
			unexpected.append(line)
	assert_eq(unexpected.size(), 0, "\n".join(unexpected.slice(0, 20)))
	assert_eq(missing.size(), 8, "the plinths of THEME_JUNM.WAD")
	assert_gt(built, 300)
