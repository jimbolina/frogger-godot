extends GutTest
## Views draw committed meshes from their own material copies, so the frog's depth bias and a view's projection never reach the shared imported materials but do reach every surface the copy draws, flipbook cels included.

const FROG: String = "GEN_FROG.XAR"
const FISH: String = "SUB_FISH.XMR"

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

func test_an_x4_catalog_retextures_the_copy_and_leaves_the_shared_mesh_retail() -> void:
	var shared: ModelMesh = _committed_frog()
	var x4: ImportedAssets = ImportedAssets.open("res://assets", "x4")
	assert_eq(x4.warnings, PackedStringArray())
	var copy: ModelMesh = ModelMeshCopy.of(shared, x4)
	var copied: Array[ShaderMaterial] = _surface_materials(copy)
	var shared_materials: Array[ShaderMaterial] = _surface_materials(shared)
	assert_eq(copied.size(), shared_materials.size())
	var textured: int = 0
	for index: int in copied.size():
		var retail: Texture2D = shared_materials[index].get_shader_parameter("image")
		var image: Texture2D = copied[index].get_shader_parameter("image")
		if retail == null:
			assert_null(image)
			assert_same(copied[index].shader, shared_materials[index].shader, "a flat material keeps its shader")
			continue
		textured += 1
		assert_true(retail.resource_path.begins_with("res://assets/textures/images/"), retail.resource_path)
		assert_eq(image.resource_path, retail.resource_path.replace("/images/", "/images_x4/"))
		assert_eq(image.get_size(), retail.get_size() * 4)
		assert_true(copied[index].shader.resource_path.contains("_linear"), copied[index].shader.resource_path)
		assert_false(shared_materials[index].shader.resource_path.contains("_linear"))
	assert_gt(textured, 0, "the frog has textured surfaces")
	var again: ModelMesh = ModelMeshLibrary.mesh_for(x4, _data.find_resource(FROG).index, null, null)
	assert_same(ModelMeshLibrary.mesh_for(x4, _data.find_resource(FROG).index, null, null), again, "the x4 mesh loads once per set")
	assert_ne(again, shared)
	assert_same(_committed_frog(), shared, "the retail mesh is untouched")

func test_the_linear_variant_is_found_from_the_shader_file() -> void:
	var opaque: Shader = ModelShaders.shader(true, ModelShaders.Blend.OPAQUE, false, false)
	assert_same(ModelShaders.linear_variant(opaque), ModelShaders.shader(true, ModelShaders.Blend.OPAQUE, true, false))
	var two_sided: Shader = ModelShaders.shader(true, ModelShaders.Blend.ADD_QUARTER, false, true)
	assert_same(ModelShaders.linear_variant(two_sided), ModelShaders.shader(true, ModelShaders.Blend.ADD_QUARTER, true, true))
	var linear: Shader = ModelShaders.shader(true, ModelShaders.Blend.AVERAGE, true, false)
	assert_same(ModelShaders.linear_variant(linear), linear)
	var flat: Shader = ModelShaders.shader(false, ModelShaders.Blend.OPAQUE, false, false)
	assert_same(ModelShaders.linear_variant(flat), flat)
	assert_null(ModelShaders.linear_variant(null))
