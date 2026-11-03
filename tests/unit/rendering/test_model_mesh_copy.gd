extends GutTest
## Views draw committed meshes from their own material copies, so the frog's depth bias and a view's projection never reach the shared imported materials but do reach every surface the copy draws, flipbook cels included.

const FROG: String = "GEN_FROG.XAR"
const FISH: String = "SUB_FISH.XMR"
const HI_A_MESH: String = "res://assets/models/options/HI_A/mesh.res"
const LETTERING_ROOT: String = "res://tests/fixtures/lettering"
const LETTERED: String = "res://assets/textures/images/t0263.png"

var _data: ImportedAssets

func before_all() -> void:
	_data = ImportedAssets.open()

func _committed_frog() -> ModelMesh:
	var entry: MwiEntry = _data.find_resource(FROG)
	return ModelMeshLibrary.mesh_for(_data, entry.index, null, null)

func _surface_materials(mesh: ModelMesh) -> Array[ShaderMaterial]:
	var found: Array[ShaderMaterial] = []
	for part: ArrayMesh in mesh.part_meshes:
		if part == null:
			continue
		for surface: int in part.get_surface_count():
			var material: ShaderMaterial = part.surface_get_material(surface) as ShaderMaterial
			if material != null:
				found.append(material)
	return found

func _parameters(materials: Array[ShaderMaterial]) -> Array:
	var values: Array = []
	for material: ShaderMaterial in materials:
		values.append([material.get_shader_parameter("depth_bias"), material.get_shader_parameter("projection_scale")])
	return values

func test_a_copy_owns_one_material_per_surface() -> void:
	assert_eq(_data.error, "")
	var shared: ModelMesh = _committed_frog()
	assert_same(_committed_frog(), shared, "a committed mesh loads once")
	var shared_materials: Array[ShaderMaterial] = _surface_materials(shared)
	assert_false(shared_materials.is_empty())
	var from_files: int = 0
	for material: ShaderMaterial in shared_materials:
		if material.resource_path.begins_with("res://assets/materials/"):
			from_files += 1
	assert_gt(from_files, 0, "the frog draws shared material files")
	var copy: ModelMesh = ModelMeshCopy.of(shared)
	assert_eq(copy.part_meshes.size(), shared.part_meshes.size())
	assert_eq(copy.morph_meshes.size(), shared.morph_meshes.size())
	assert_eq(copy.bounds, shared.bounds)
	var copied: Array[ShaderMaterial] = _surface_materials(copy)
	assert_eq(copied.size(), shared_materials.size())
	for index: int in copied.size():
		assert_ne(copied[index], shared_materials[index])
		assert_eq(copied[index].shader, shared_materials[index].shader)
		assert_eq(copied[index].resource_path, "")
	var distinct: Dictionary[ShaderMaterial, bool] = {}
	for material: ShaderMaterial in copied:
		distinct[material] = true
	assert_eq(distinct.size(), copied.size(), "every surface owns its own copy, so flipbook parts never share a cel pose")
	for part: int in copy.texture_tracks.size():
		for track: ModelMesh.TextureTrack in copy.texture_tracks[part]:
			assert_same(track.original, copy.part_meshes[part].surface_get_material(track.surface), "a track's original is its surface's copy")
	for part: int in shared.part_meshes.size():
		if shared.part_meshes[part] != null:
			assert_eq(copy.part_meshes[part].get_surface_count(), shared.part_meshes[part].get_surface_count())
			assert_eq(copy.part_meshes[part].get_blend_shape_count(), shared.part_meshes[part].get_blend_shape_count())
	assert_null(ModelMeshCopy.of(null))

func test_biasing_one_frog_leaves_the_other_and_the_shared_materials_untouched() -> void:
	var shared: ModelMesh = _committed_frog()
	var before: Array = _parameters(_surface_materials(shared))
	var view := GameplayWorldView.new()
	add_child_autofree(view)
	view.build_world()
	view.build_frog(TerrainFrogAssets.from_data(_data))
	view._projection_size = Vector2i.ZERO
	view._update_projection()
	var other := AnimatedModelInstance.new()
	add_child_autofree(other)
	other.setup(_committed_frog(), TerrainFrogAssets.from_data(_data).player)
	assert_eq(_parameters(_surface_materials(shared)), before, "the shared materials are unchanged")
	var biased: Array[ShaderMaterial] = _surface_materials(view.frog_assets.mesh)
	assert_false(biased.is_empty())
	for material: ShaderMaterial in biased:
		var bias: float = material.get_shader_parameter("depth_bias")
		assert_eq(bias, GameplayWorldView.FROG_DEPTH_BIAS)
	for node: MeshInstance3D in other.part_nodes:
		var mesh: ArrayMesh = node.mesh as ArrayMesh
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var drawn: ShaderMaterial = node.get_surface_override_material(surface) as ShaderMaterial
			if drawn == null:
				drawn = mesh.surface_get_material(surface) as ShaderMaterial
			if drawn != null:
				var bias: String = str(drawn.get_shader_parameter("depth_bias"))
				assert_ne(bias, str(GameplayWorldView.FROG_DEPTH_BIAS), "the other frog is not biased")

func test_the_frog_hides_the_parts_froglord_hides() -> void:
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(_data)
	assert_eq(assets.error, "")
	assert_eq(assets.hidden_parts, PackedInt64Array([GameplayWorldView.THROAT_PART]))
	var copy: TerrainFrogAssets = assets.with_mesh(ModelMesh.new())
	assert_same(copy.model, assets.model)
	assert_same(copy.player, assets.player)
	assert_eq(copy.hidden_parts, assets.hidden_parts)
	assert_ne(copy.mesh, assets.mesh)

func test_a_flipbook_copy_draws_its_part_materials_so_the_projection_reaches_its_cels() -> void:
	var entry: MwiEntry = _data.find_resource(FISH)
	assert_not_null(entry)
	var copy: ModelMesh = ModelMeshCopy.of(ModelMeshLibrary.mesh_for(_data, entry.index, null, null))
	var morph_parts: int = 0
	for part: int in copy.morph_meshes.size():
		var morph: ModelMorphMesh = copy.morph_meshes[part]
		if morph == null:
			continue
		morph_parts += 1
		for surface: int in morph.mesh.get_surface_count():
			assert_same(morph.mesh.surface_get_material(surface), copy.part_meshes[part].surface_get_material(surface), "a morph surface draws its part surface's copy, as a built mesh does")
	assert_gt(morph_parts, 0, "the fish has flipbook parts")
	var scale := Vector2(1.0, 0.9375)
	var view := GameplayWorldView.new()
	add_child_autofree(view)
	view._set_model_projection(copy, scale)
	var instance := AnimatedModelInstance.new()
	add_child_autofree(instance)
	instance.setup(copy, ModelAnimationPlayer.new(_data.read_model(entry.index)))
	var checked: int = 0
	for part: int in instance.part_nodes.size():
		if copy.morph_meshes[part] == null:
			continue
		var node: MeshInstance3D = instance.part_nodes[part]
		for surface: int in node.mesh.get_surface_count():
			var drawn: ShaderMaterial = node.get_surface_override_material(surface) as ShaderMaterial
			assert_not_null(drawn)
			var value: Variant = drawn.get_shader_parameter("projection_scale")
			var projection := Vector2.ZERO
			if value is Vector2:
				projection = value
			assert_eq(projection, scale, "the view's projection reaches the flipbook cels")
			checked += 1
	assert_gt(checked, 0)

func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(child))
	for child: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)

func test_a_texture_pack_retextures_the_copy_per_texture_and_leaves_the_shared_mesh_retail() -> void:
	var packs: String = "user://test_model_mesh_copy_packs"
	var folder: String = packs.path_join("frog_pack")
	_remove(packs)
	assert_eq(DirAccess.make_dir_recursive_absolute(folder), OK)
	var config := ConfigFile.new()
	config.set_value("pack", "name", "Frog pack")
	config.set_value("pack", "base_build", _data.version_name)
	assert_eq(config.save(folder.path_join("pack.cfg")), OK)
	var shared: ModelMesh = _committed_frog()
	var shared_materials: Array[ShaderMaterial] = _surface_materials(shared)
	var retail_paths := PackedStringArray()
	for material: ShaderMaterial in shared_materials:
		var retail: Texture2D = material.get_shader_parameter("image")
		if retail != null and not retail_paths.has(retail.resource_path):
			retail_paths.append(retail.resource_path)
	assert_gt(retail_paths.size(), 1, "the frog draws several textures")
	var kept: String = retail_paths[0]
	for path: String in retail_paths.slice(1):
		var pixels: Image = (load(path) as Texture2D).get_image()
		pixels.resize(pixels.get_width() * 2, pixels.get_height() * 2, Image.INTERPOLATE_NEAREST)
		assert_eq(pixels.save_png(folder.path_join(path.get_file())), OK)
	var catalog: ImportedAssets = ImportedAssets.open("res://assets", "frog_pack", "", "res://assets", PackedStringArray([packs]))
	assert_eq(catalog.warnings, PackedStringArray())
	var copy: ModelMesh = ModelMeshCopy.of(shared, catalog)
	var copied: Array[ShaderMaterial] = _surface_materials(copy)
	assert_eq(copied.size(), shared_materials.size())
	var replaced: int = 0
	for index: int in copied.size():
		var retail: Texture2D = shared_materials[index].get_shader_parameter("image")
		var image: Texture2D = copied[index].get_shader_parameter("image")
		if retail == null or retail.resource_path == kept:
			assert_same(image, retail, "a texture the pack omits stays retail")
			assert_same(copied[index].shader, shared_materials[index].shader, "and keeps its shader")
			continue
		replaced += 1
		assert_eq(image.get_size(), retail.get_size() * 2)
		assert_true(image.get_image().has_mipmaps(), "a scaled pack image has mipmaps")
		assert_true(copied[index].shader.resource_path.contains("_linear"), copied[index].shader.resource_path)
		assert_false(shared_materials[index].shader.resource_path.contains("_linear"))
	assert_gt(replaced, 0, "the pack retextures the frog")
	assert_eq(catalog.texture_set().scale_of(TextureSet.texture_id_of(retail_paths[1])), 2)
	var again: ModelMesh = ModelMeshLibrary.mesh_for(catalog, _data.find_resource(FROG).index, null, null)
	assert_same(ModelMeshLibrary.mesh_for(catalog, _data.find_resource(FROG).index, null, null), again,
		"the pack's mesh converts once per pack")
	assert_ne(again, shared)
	assert_same(_committed_frog(), shared, "the retail mesh is untouched")
	_remove(packs)

func test_the_linear_variant_is_found_from_the_shader_file() -> void:
	var opaque: Shader = ModelShaders.shader(true, ModelShaders.Blend.OPAQUE, false, false)
	assert_same(ModelShaders.linear_variant(opaque), ModelShaders.shader(true, ModelShaders.Blend.OPAQUE, true, false))
	var two_sided: Shader = ModelShaders.shader(true, ModelShaders.Blend.ADD_QUARTER, false, true)
	assert_same(ModelShaders.linear_variant(two_sided), ModelShaders.shader(true, ModelShaders.Blend.ADD_QUARTER, true, true))
	var linear: Shader = ModelShaders.shader(true, ModelShaders.Blend.AVERAGE, true, false)
	assert_same(ModelShaders.linear_variant(linear), linear)
	var flat: Shader = ModelShaders.shader(false, ModelShaders.Blend.OPAQUE, false, false)
	assert_same(ModelShaders.linear_variant(flat), flat)
	var unlit: Shader = ModelShaders.shader(true, ModelShaders.Blend.SUBTRACT, false, true, false)
	assert_same(ModelShaders.linear_variant(unlit), ModelShaders.shader(true, ModelShaders.Blend.SUBTRACT, true, true, false))
	var unlit_flat: Shader = ModelShaders.shader(false, ModelShaders.Blend.ADD, false, true, false)
	assert_same(ModelShaders.linear_variant(unlit_flat), unlit_flat)
	assert_null(ModelShaders.linear_variant(null))

func test_committed_materials_draw_through_the_lit_shaders() -> void:
	var materials: Array[ShaderMaterial] = _surface_materials(_committed_frog())
	assert_false(materials.is_empty())
	for material: ShaderMaterial in materials:
		var path: String = material.shader.resource_path
		assert_eq(path.get_base_dir(), ModelShaders.SHADER_DIR, path)
		assert_false(path.get_file().begins_with(ModelShaders.UNLIT_PREFIX), path)
		assert_string_contains(material.shader.code, "#include \"model.gdshaderinc\"", path)
		assert_false(material.shader.code.contains("unshaded"), path)

func test_the_retail_set_keeps_the_shared_mesh_and_its_shaders() -> void:
	var shared: ModelMesh = _committed_frog()
	var copied: Array[ShaderMaterial] = _surface_materials(ModelMeshCopy.of(shared, _data))
	var shared_materials: Array[ShaderMaterial] = _surface_materials(shared)
	for index: int in copied.size():
		assert_same(copied[index].shader, shared_materials[index].shader)
		var image: Texture2D = copied[index].get_shader_parameter("image")
		var shared_image: Texture2D = shared_materials[index].get_shader_parameter("image")
		assert_same(image, shared_image)
	assert_same(ModelMeshLibrary.mesh_for(_data, _data.find_resource(FROG).index, null, null), shared)

func _lettered() -> ImportedAssets:
	var catalog := ImportedAssets.new()
	catalog.shippable_root = LETTERING_ROOT
	return catalog

func _all_materials(mesh: ModelMesh) -> Array[ShaderMaterial]:
	var found: Array[ShaderMaterial] = _surface_materials(mesh)
	for tracks: Array in mesh.texture_tracks:
		for track: ModelMesh.TextureTrack in tracks:
			found.append(track.original)
			found.append_array(track.frames)
	return found

func test_a_retail_mesh_with_lettering_draws_it_through_the_linear_shader() -> void:
	var shared: ModelMesh = load(HI_A_MESH) as ModelMesh
	var lettered: ImportedAssets = _lettered()
	var key: String = LETTERING_ROOT.path_join("models/options/HI_A/mesh.res")
	var drawn: ModelMesh = ModelMeshLibrary._for_drawing(shared, key, lettered)
	assert_ne(drawn, shared)
	assert_same(ModelMeshLibrary._for_drawing(shared, key, lettered), drawn, "one copy per path and set")
	var copied: Array[ShaderMaterial] = _all_materials(drawn)
	var shared_materials: Array[ShaderMaterial] = _all_materials(shared)
	assert_eq(copied.size(), shared_materials.size())
	var swapped: int = 0
	for index: int in copied.size():
		var retail: Texture2D = shared_materials[index].get_shader_parameter("image")
		var image: Texture2D = copied[index].get_shader_parameter("image")
		if retail == null or retail.resource_path != LETTERED:
			assert_same(image, retail)
			assert_same(copied[index].shader, shared_materials[index].shader, "other images keep their shader")
			continue
		swapped += 1
		assert_eq(image.resource_path, LETTERING_ROOT.path_join("lettering/t0263.png"))
		assert_same(copied[index].shader, ModelShaders.linear_variant(shared_materials[index].shader))
		assert_true(copied[index].shader.resource_path.contains("_linear"), copied[index].shader.resource_path)
		assert_false(shared_materials[index].shader.resource_path.contains("_linear"))
	assert_gt(swapped, 0, "HI_A draws its lettered lily pad")
	assert_same(load(HI_A_MESH) as ModelMesh, shared, "the shared mesh keeps its retail textures")

func test_a_retail_mesh_without_lettering_is_drawn_shared() -> void:
	var shared: ModelMesh = _committed_frog()
	var key: String = LETTERING_ROOT.path_join("models/GEN_FROG/mesh.res")
	assert_same(ModelMeshLibrary._for_drawing(shared, key, _lettered()), shared)
	assert_same(ModelMeshLibrary._for_drawing(shared, key, _lettered()), shared)
