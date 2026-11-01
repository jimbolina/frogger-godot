extends GutTest
## The front-end pages built from the committed assets draw their stack boxes and options models
## through the lit shaders under one scene light per world; the water stays unlit.

const LIT: String = "lit"
const UNLIT: String = "unlit"

var _data: ImportedAssets
var _assets: FrontEndAssets
var _models: OptionsModels


func before_all() -> void:
	_data = ImportedAssets.open()
	_assets = FrontEndAssets.from_data(_data)
	_models = OptionsModels.from_data(_data)


func after_all() -> void:
	_data.close()


func _shader_kinds(nodes: Array[MeshInstance3D]) -> Dictionary[String, int]:
	var kinds: Dictionary[String, int] = {}
	for node: MeshInstance3D in nodes:
		if node == null or node.mesh == null:
			continue
		for surface: int in node.mesh.get_surface_count():
			var material: ShaderMaterial = node.get_active_material(surface) as ShaderMaterial
			var path: String = material.shader.resource_path if material != null and material.shader != null else ""
			var lit: bool = path.get_base_dir() == ModelShaders.SHADER_DIR and path.get_file().begins_with("model_") \
				and not path.get_file().begins_with(ModelShaders.UNLIT_PREFIX)
			var kind: String = LIT if lit else UNLIT
			var count: int = kinds.get(kind, 0)
			kinds[kind] = count + 1
	return kinds


func _part_nodes(instances: Array[AnimatedModelInstance]) -> Array[MeshInstance3D]:
	var nodes: Array[MeshInstance3D] = []
	for instance: AnimatedModelInstance in instances:
		if instance != null:
			nodes.append_array(instance.part_nodes)
	return nodes


func test_the_assets_open() -> void:
	assert_eq(_data.error, "")
	assert_eq(_assets.error, "")
	assert_eq(_models.error, "")


func test_the_stack_page_draws_every_box_lit() -> void:
	var stack: LevelStack = LevelProgressSetup.stack_from_table(_data.tables.level_select())
	var view: LevelStackView = LevelStackView.create(_assets, stack, LevelProgress.create(stack), -1, true, Color.BLACK, MenuWater.create())
	add_child_autofree(view)
	assert_eq(_shader_kinds(view.boxes), {LIT: view.boxes.size() * 2})
	assert_not_null(view.scene_lighting)
	assert_eq(view.scene_lighting.light_nodes().size(), 3)
	assert_eq(view.find_children("*", "WorldEnvironment", true, false).size(), 1)
	var water_nodes: Array[MeshInstance3D] = [view.water.surface, view.water.riverbed]
	assert_false(_shader_kinds(water_nodes).has(LIT), "the water stays unlit")
	for _tick: int in 8:
		view.tick(StackSelector.Buttons.new())
	view.tick(StackSelector.Buttons.new(false, false, true))
	var spin: Array[MeshInstance3D] = [view.spin_box, view.spin_picture]
	assert_eq(_shader_kinds(spin), {LIT: 2})


func test_the_options_page_draws_its_models_lit() -> void:
	var view: OptionsView = OptionsView.create(_assets, MenuWater.create(), OptionsCamera.new(), 3, 5,
		OptionsMenu.Row.EXIT, true, _models)
	add_child_autofree(view)
	var nodes: Array[MeshInstance3D] = _part_nodes(view.model_instances())
	assert_gt(nodes.size(), 0)
	assert_eq(_shader_kinds(nodes).keys(), [LIT])
	assert_not_null(view.water.scene_lighting)
	assert_eq(view.water.scene_lighting.light_nodes().size(), 1)
	assert_eq(view.find_children("*", "WorldEnvironment", true, false).size(), 1)


func test_the_main_menu_table_draws_its_models_lit() -> void:
	var table: HighScoreTable = _data.tables.high_scores()
	var board: HighScoreBoard = HighScoreBoard.create(
		FrontEndSession.rows_of(table.main_initials, table.main_scores, table.main_times),
		FrontEndSession.rows_of(table.level_initials, table.level_scores, table.level_times))
	var water: MenuWaterView = MenuWaterView.create_with_camera(MenuWater.create(), _assets.texture("opt_env_sky"), _assets.texture("opt_bank3"))
	add_child_autofree(water)
	var scene_view: HighScoreSceneView = HighScoreSceneView.create_for(HighScoreScene.create(board.main), _models)
	water.add_child(scene_view)
	var nodes: Array[MeshInstance3D] = _part_nodes(scene_view.model_instances())
	assert_gt(nodes.size(), 0)
	assert_eq(_shader_kinds(nodes).keys(), [LIT])
	assert_not_null(scene_view.scene_lighting)
	assert_eq(scene_view.scene_lighting.light_nodes().size(), 1)
	assert_null(water.world_environment, "the water gives up its environment")
