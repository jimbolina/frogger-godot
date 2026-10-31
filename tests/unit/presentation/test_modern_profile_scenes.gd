extends GutTest
## A level opened under the modern profile draws its terrain, frog and entities with the lit
## shaders under scene lights; under the retail profile it keeps the retail shaders and no lights.

const MODERN_SHADERS: String = "res://src/convert/shaders/modern"
const RETAIL_SHADERS: String = "res://src/convert/shaders"

var _modern: ImportedAssets
var _retail: ImportedAssets


func before_all() -> void:
	_modern = ImportedAssets.open("res://assets", "", RenderingProfile.MODERN)
	_retail = ImportedAssets.open()


func after_all() -> void:
	_modern.close()
	_retail.close()


func _open(data: ImportedAssets) -> GameplayScreen:
	var screen := GameplayScreen.new()
	screen.auto_open = false
	add_child_autofree(screen)
	screen.set_process(false)
	assert_eq(screen.open_data(data, "ORG1"), "")
	return screen


func _shader_paths(nodes: Array[MeshInstance3D]) -> Dictionary[String, bool]:
	var paths: Dictionary[String, bool] = {}
	for node: MeshInstance3D in nodes:
		if node == null or node.mesh == null:
			continue
		for surface: int in node.mesh.get_surface_count():
			var material: ShaderMaterial = node.get_active_material(surface) as ShaderMaterial
			paths[material.shader.resource_path if material != null and material.shader != null else "<none>"] = true
	return paths


func _terrain_nodes(screen: GameplayScreen) -> Array[MeshInstance3D]:
	var nodes: Array[MeshInstance3D] = []
	for child: Node in screen._map_instance.get_children():
		if child is MeshInstance3D:
			nodes.append(child as MeshInstance3D)
	return nodes


func _model_nodes(screen: GameplayScreen) -> Array[MeshInstance3D]:
	var nodes: Array[MeshInstance3D] = []
	nodes.append_array(screen._frog_model.part_nodes)
	for model: AnimatedModelInstance in screen._entity_models:
		if model != null:
			nodes.append_array(model.part_nodes)
	return nodes


func _count(screen: GameplayScreen, type: String) -> int:
	return screen.find_children("*", type, true, false).size()


func _assert_all_in(paths: Dictionary[String, bool], directory: String, what: String) -> void:
	assert_false(paths.is_empty(), "%s draws surfaces" % what)
	for path: String in paths:
		assert_eq(path.get_base_dir(), directory, "%s shader %s" % [what, path])


func test_org1_under_the_modern_profile_is_lit_with_the_modern_shaders() -> void:
	assert_eq(_modern.error, "")
	assert_true(_modern.rendering_profile().is_modern())
	assert_eq(_modern.warnings, PackedStringArray(), "opening the modern profile warns of nothing")
	var note: String = _modern.note_renderer(RenderingServer.get_current_rendering_method())
	assert_eq(_modern.warnings, PackedStringArray([note]) if not note.is_empty() else PackedStringArray(), "only the renderer note is reported")
	var screen: GameplayScreen = _open(_modern)
	assert_true(screen.rendering_profile.is_modern())
	assert_eq(_count(screen, "WorldEnvironment"), 1)
	var lights: Array[DirectionalLight3D] = screen.scene_lighting.light_nodes()
	assert_eq(_count(screen, "DirectionalLight3D"), lights.size())
	var casters: int = 0
	for light: DirectionalLight3D in lights:
		if light.shadow_enabled:
			casters += 1
	assert_eq(casters, 1, "one light casts the shadows")
	assert_not_null(screen.scene_lighting.environment)
	assert_ne(screen.scene_lighting.applied_ambient, Vector3.ONE)
	_assert_all_in(_shader_paths(_terrain_nodes(screen)), MODERN_SHADERS, "terrain")
	assert_gt(screen.entity_model_count(), 0)
	_assert_all_in(_shader_paths(_model_nodes(screen)), MODERN_SHADERS, "frog and entity part")
	screen.close_data()


func test_org1_under_the_retail_profile_keeps_the_retail_shaders_and_no_lights() -> void:
	assert_eq(_retail.error, "")
	var screen: GameplayScreen = _open(_retail)
	assert_false(screen.rendering_profile.is_modern())
	assert_eq(_count(screen, "WorldEnvironment"), 0)
	assert_eq(_count(screen, "DirectionalLight3D"), 0)
	assert_null(screen.scene_lighting.environment)
	assert_eq(screen.scene_lighting.applied_ambient, Vector3.ONE)
	_assert_all_in(_shader_paths(_terrain_nodes(screen)), RETAIL_SHADERS, "terrain")
	assert_gt(screen.entity_model_count(), 0)
	_assert_all_in(_shader_paths(_model_nodes(screen)), RETAIL_SHADERS, "frog and entity part")
	screen.close_data()
