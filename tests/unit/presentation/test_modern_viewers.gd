extends GutTest
## The tool viewers under the modern profile, from the committed assets: the
## model viewer lights GEN_FROG with the options lights, the camera-zone viewer
## lights JUN1 from its map, and the terrain viewer applies the map lights only
## when the scenario's contract includes entity lighting. Retail creates no lights.

const MODERN_SHADERS: String = "res://src/convert/shaders/modern"
const RETAIL_SHADERS: String = "res://src/convert/shaders"
const MODEL_VIEWER_SCENE: String = "res://scenes/tools/model_viewer.tscn"

var _modern: ImportedAssets
var _retail: ImportedAssets


func before_all() -> void:
	_modern = ImportedAssets.open("res://assets", "", RenderingProfile.MODERN)
	_retail = ImportedAssets.open()


func after_all() -> void:
	_modern.close()
	_retail.close()


func _shader_paths(nodes: Array[MeshInstance3D]) -> Dictionary[String, bool]:
	var paths: Dictionary[String, bool] = {}
	for node: MeshInstance3D in nodes:
		if node == null or node.mesh == null:
			continue
		for surface: int in node.mesh.get_surface_count():
			var material: ShaderMaterial = node.get_active_material(surface) as ShaderMaterial
			paths[material.shader.resource_path if material != null and material.shader != null else "<none>"] = true
	return paths


func _assert_all_in(paths: Dictionary[String, bool], directory: String, what: String) -> void:
	assert_false(paths.is_empty(), "%s draws surfaces" % what)
	for path: String in paths:
		assert_eq(path.get_base_dir(), directory, "%s shader %s" % [what, path])


func _count(root: Node, type: String) -> int:
	return root.find_children("*", type, true, false).size()


func _model_viewer(data: ImportedAssets) -> ModelViewer:
	var packed: PackedScene = load(MODEL_VIEWER_SCENE)
	var viewer: ModelViewer = packed.instantiate() as ModelViewer
	viewer.auto_open = false
	add_child_autofree(viewer)
	viewer.open_data(data)
	assert_gt(viewer.load_model_by_name("GEN_FROG.XAR"), 0)
	return viewer


func _terrain_viewer(data: ImportedAssets, preset: String, level: String) -> TerrainViewer:
	var viewer := TerrainViewer.new()
	viewer.auto_open = false
	add_child_autofree(viewer)
	viewer.set_process(false)
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--exploration=" + preset, "--level=" + level])), "")
	assert_eq(viewer.open_scenario(scenario), "")
	scenario.level_code = level
	assert_eq(viewer.open_data(data), "")
	return viewer


func test_model_viewer_lights_gen_frog_with_the_options_lights() -> void:
	var viewer: ModelViewer = _model_viewer(_modern)
	assert_not_null(viewer.scene_lighting)
	var expected: int = SceneLightingBuilder.from_lighting(OptionsModels.options_lighting(), false).lights.size()
	assert_gt(expected, 0)
	assert_eq(viewer.scene_lighting.light_nodes().size(), expected)
	assert_eq(_count(viewer, "DirectionalLight3D"), expected)
	for light: DirectionalLight3D in viewer.scene_lighting.light_nodes():
		assert_false(light.shadow_enabled, "the viewer casts no shadows")
	assert_eq(viewer.scene_lighting.environment.background_mode, Environment.BG_CLEAR_COLOR, "the grey backdrop stays")
	_assert_all_in(_shader_paths(viewer.animated_instance.part_nodes), MODERN_SHADERS, "GEN_FROG part")
	viewer._filter_toggle.button_pressed = true
	var linear: bool = false
	for path: String in _shader_paths(viewer.animated_instance.part_nodes):
		assert_eq(path.get_base_dir(), MODERN_SHADERS)
		linear = linear or path.get_file().contains("_linear")
	assert_true(linear, "the filter toggle selects the lit linear variants")
	assert_eq(_count(viewer, "DirectionalLight3D"), expected, "rebuilding keeps one set of lights")


func test_model_viewer_under_retail_shows_the_unlit_colours_without_lights() -> void:
	var viewer: ModelViewer = _model_viewer(_retail)
	assert_null(viewer.scene_lighting)
	assert_eq(_count(viewer, "DirectionalLight3D"), 0)
	assert_eq(_count(viewer, "WorldEnvironment"), 0)
	_assert_all_in(_shader_paths(viewer.animated_instance.part_nodes), RETAIL_SHADERS, "GEN_FROG part")


func test_camera_zone_viewer_lights_jun1_from_its_map() -> void:
	var viewer := CameraZoneViewer.new()
	viewer.auto_open = false
	add_child_autofree(viewer)
	viewer.set_process(false)
	assert_eq(viewer.open(_modern, true), "")
	assert_not_null(viewer.scene_lighting)
	var lighting := MapLighting.new()
	lighting.configure(viewer.inspection.map_scene.map.lights)
	assert_eq(viewer.scene_lighting.light_nodes().size(), SceneLightingBuilder.from_lighting(lighting).lights.size())
	assert_gt(viewer.scene_lighting.light_nodes().size(), 0)
	assert_eq(_count(viewer, "WorldEnvironment"), 1)
	assert_true(_modern.is_valid(), "the borrowed catalog stays open")


func test_camera_zone_viewer_under_retail_has_no_lights() -> void:
	var viewer := CameraZoneViewer.new()
	viewer.auto_open = false
	add_child_autofree(viewer)
	viewer.set_process(false)
	assert_eq(viewer.open(_retail, true), "")
	assert_null(viewer.scene_lighting)
	assert_eq(_count(viewer, "DirectionalLight3D"), 0)
	assert_eq(_count(viewer, "WorldEnvironment"), 0)


func test_terrain_viewer_lights_a_lit_scenario_from_the_map() -> void:
	var viewer: TerrainViewer = _terrain_viewer(_modern, Org1ExplorationSetup.PRESET, "ORG1")
	assert_true(TerrainCaptureStages.entity_lighting(viewer.scenario))
	assert_true(viewer.rendering_profile.is_modern(), "the viewer takes the catalog's profile")
	assert_gt(viewer.scene_lighting.light_nodes().size(), 0)
	assert_eq(_count(viewer, "DirectionalLight3D"), viewer.scene_lighting.light_nodes().size())
	assert_ne(viewer.scene_lighting.applied_ambient, Vector3.ONE)
	assert_gt(viewer.entity_model_count(), 0)


func test_terrain_viewer_keeps_an_unlit_scenario_free_of_lights() -> void:
	var viewer: TerrainViewer = _terrain_viewer(_modern, "jun1-log-bank", "JUN1")
	assert_false(TerrainCaptureStages.entity_lighting(viewer.scenario))
	assert_true(viewer.rendering_profile.is_modern())
	assert_eq(viewer.scene_lighting.light_nodes().size(), 0)
	assert_eq(_count(viewer, "DirectionalLight3D"), 0)
	assert_eq(viewer.scene_lighting.applied_ambient, Vector3.ONE, "stored colours under a full flat ambient")
	assert_not_null(viewer.scene_lighting.environment)
	assert_true(viewer.scene_lighting.applied_spec.lights.is_empty())


func test_terrain_viewer_under_retail_creates_no_lights_for_either_scenario() -> void:
	for row: Array in [[Org1ExplorationSetup.PRESET, "ORG1"], ["jun1-log-bank", "JUN1"]]:
		var preset: String = row[0]
		var level: String = row[1]
		var viewer: TerrainViewer = _terrain_viewer(_retail, preset, level)
		assert_false(viewer.rendering_profile.is_modern())
		assert_eq(_count(viewer, "DirectionalLight3D"), 0, preset)
		assert_eq(_count(viewer, "WorldEnvironment"), 0, preset)
		assert_null(viewer.scene_lighting.environment, preset)
