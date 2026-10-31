extends RetailTest
## Real player resources exercise live terrain viewer attachment and release.

func _data() -> GameData:
	return GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func _viewer() -> TerrainViewer:
	var viewer := TerrainViewer.new()
	viewer.auto_open = false
	add_child_autofree(viewer)
	viewer.set_process(false)
	return viewer

func test_live_frog_attachment_releases_replaced_render_resources() -> void:
	var data: GameData = _data()
	assert_true(data.is_valid(), data.error)
	var viewer: TerrainViewer = _viewer()
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(viewer.open_scenario(scenario), "")
	for repeat: int in 3:
		assert_eq(viewer.open_data(data), "")
		assert_same(viewer.frog_assets.model, scenario.frog_assets.model, "Setup and drawing share one frog record")
		assert_same(viewer.frog_assets.player, scenario.frog_assets.player, "Setup and drawing share one animation player")
		assert_not_null(viewer._frog_model)
		var old_assets: WeakRef = weakref(viewer.frog_assets)
		var old_mesh: WeakRef = weakref(viewer.frog_assets.mesh)
		assert_eq(viewer.open_data(null), "")
		assert_not_null(viewer.run, "Synthetic detached inputs remain usable")
		assert_null(viewer._frog_model)
		assert_null(scenario.frog_assets)
		await get_tree().process_frame
		var released_assets: Object = old_assets.get_ref()
		var released_mesh: Object = old_mesh.get_ref()
		assert_null(released_assets)
		assert_null(released_mesh)
		assert_not_null(data.archive._file, "Borrowed archive remains open")
	data.close()

func test_selected_level_rebind_clears_old_scene_and_preserves_owned_source() -> void:
	var first: GameData = _data()
	var second: GameData = _data()
	var viewer: TerrainViewer = _viewer()
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	scenario.level_code = "ORG3"
	assert_eq(viewer.open_scenario(scenario), "")
	assert_eq(viewer.open_data(first), "")
	assert_not_null(scenario.map_scene)
	var old_scene: WeakRef = weakref(scenario.map_scene)
	var old_mesh: WeakRef = weakref(viewer._map_instance.source)
	assert_eq(viewer.open_data(second, true), "")
	assert_same(viewer.data, second)
	assert_not_null(viewer.run)
	assert_same(viewer._map_instance.source.scene, scenario.map_scene)
	assert_not_null(first.archive._file)
	await get_tree().process_frame
	var released_scene: Object = old_scene.get_ref()
	var released_mesh: Object = old_mesh.get_ref()
	assert_null(released_scene)
	assert_null(released_mesh)
	assert_eq(viewer.open_data(second), "")
	assert_true(viewer._owns_data, "Same source reattachment retains ownership")
	assert_not_null(second.archive._file)
	assert_eq(viewer.open_data(null), "")
	assert_null(second.archive._file)
	assert_null(viewer.run)
	assert_null(scenario.map_scene)
	assert_eq(viewer._ground.get_child_count(), 0)
	assert_false(viewer._label.text.contains("pc-retail"))
	first.close()
