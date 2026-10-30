extends RetailTest
## The options page's models, frog, sprite images and lights load from the retail files by
## FrogLord name, and a page drawn with them places every model and animates the volume logs and
## the frog as tests/golden/synthetic/frontend_options_models.json describes.

const LOG_ANIMATED_POLYS: int = 64


func _models() -> OptionsModels:
	var data: GameData = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))
	assert_eq(data.error, "")
	if not data.is_valid():
		return null
	var models: OptionsModels = OptionsModels.from_data(data)
	data.close()
	return models


func test_every_options_model_and_image_loads() -> void:
	var models: OptionsModels = _models()
	if models == null:
		return
	assert_eq(models.error, "")
	assert_eq(models.diagnostics, PackedStringArray())
	assert_eq(models.files.size(), OptionsModels.FILE_NAMES.size())
	for kind: int in OptionsModels.Kind.values():
		var label: String = OptionsModels.FILE_NAMES[kind]
		assert_not_null(models.model_file(kind), label)
		assert_not_null(models.model_mesh(kind), label)
		if models.model_mesh(kind) != null:
			assert_false(models.model_mesh(kind).is_empty(), label)
			assert_eq(models.model_mesh(kind).missing_image_ids, PackedInt32Array(), label + " textures")
	var log_player := ModelAnimationPlayer.new(models.model_file(OptionsModels.Kind.LOG))
	for poly: int in LOG_ANIMATED_POLYS:
		assert_true(log_player.set_animated_poly_cel(poly, OptionsMenu.LOG_CEL_HALF), "log animated poly %d" % poly)
	assert_false(log_player.set_animated_poly_cel(LOG_ANIMATED_POLYS, OptionsMenu.LOG_CEL_HALF), "the log has 64")
	assert_eq(models.frog.error, "")
	for action_name: StringName in [OptionsScene.ACTION_WAIT2, OptionsScene.ACTION_WAIT1, OptionsScene.ACTION_HOP,
			OptionsScene.ACTION_OUCH, OptionsScene.ACTION_PANT2, OptionsScene.ACTION_DANCE]:
		var action: int = OptionsScene.action_index(action_name)
		assert_gt(models.frog.action_lengths[action], 0, str(action_name))
	for symbol: String in OptionsModels.SPLASH_SYMBOLS:
		assert_true(models.images.has(symbol), symbol)
	for symbol: String in FrogShadowGeometry.PHASE_TEXTURES:
		assert_true(models.images.has(symbol), symbol)
	assert_eq(models.lighting.ambient, Vector3(0x60, 0x60, 0x60) * 16.0)
	assert_eq(models.lighting.colours, [Vector3(0xc0, 0xa0, 0xa0) * 16.0])


func test_page_places_and_animates_the_models() -> void:
	var models: OptionsModels = _models()
	if models == null or not models.error.is_empty():
		fail_test("options models: %s" % (models.error if models != null else "no data"))
		return
	var view: OptionsView = OptionsView.create(FrontEndAssets.new(), MenuWater.create(), OptionsCamera.new(), 0, 5,
		OptionsMenu.Row.EXIT, false, models)
	add_child_autofree(view)
	var scene: OptionsScene = view.scene
	var instances: Array[AnimatedModelInstance] = view.model_instances()
	assert_eq(instances.size(), scene.lilies.size() + scene.logs.size() * 2 + scene.extras.size() + 1)
	for _tick: int in OptionsMenu.FLY_ON_TIME:
		view.tick(OptionsMenu.Buttons.new())
	view.render(1.0)
	for index: int in scene.lilies.size():
		assert_eq(instances[index].transform, GameSpace.transform(scene.lilies[index]), "lily %d" % index)
	var frog: AnimatedModelInstance = instances[instances.size() - 1]
	assert_eq(frog.player.action_index, OptionsScene.action_index(OptionsScene.ACTION_WAIT2))
	for _hop: int in 2:
		view.tick(OptionsMenu.Buttons.new(OptionsMenu.Buttons.DOWN))
		assert_eq(frog.player.action_index, OptionsScene.action_index(OptionsScene.ACTION_HOP))
		for _tick: int in OptionsMenu.FROG_JUMP_TIME:
			view.tick(OptionsMenu.Buttons.new())
	assert_eq(view.menu.row_kind, OptionsMenu.Row.MUSIC)
	assert_true(view.splash_lilies().has(view.menu.row), "the landing splash is showing")
	var music_log: AnimatedModelInstance = instances[scene.lilies.size()]
	var pose: ModelPose = music_log.player.sample_pose()
	assert_eq(pose.texture_entries[0][0], OptionsMenu.LOG_CEL_BLANK, "music 0 shows blank cels")
	view.tick(OptionsMenu.Buttons.new(0, OptionsMenu.Buttons.RIGHT))
	assert_eq(frog.player.action_index, OptionsScene.action_index(OptionsScene.ACTION_DANCE))
	assert_eq(frog.player.end_mode, ModelAnimationPlayer.EndMode.LOOP)
	pose = music_log.player.sample_pose()
	assert_eq(pose.texture_entries[0][OptionsScene.LOG_POLY_INDICES[0]], OptionsMenu.LOG_CEL_HALF, "stage 1 shows half")
	assert_eq(pose.texture_entries[0][OptionsScene.LOG_POLY_INDICES[1]], OptionsMenu.LOG_CEL_BLANK, "stage 2 blank")
