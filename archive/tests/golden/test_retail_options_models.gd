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
	assert_true(models.images.has(OptionsModels.CLOUD_IMAGE), "menu cloud image")
	assert_not_null(models.image_texture(OptionsModels.CLOUD_IMAGE), "menu cloud texture")
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


func test_high_score_models_and_the_entry_frog_load() -> void:
	var models: OptionsModels = _models()
	if models == null or not models.error.is_empty():
		fail_test("options models: %s" % (models.error if models != null else "no data"))
		return
	for file_name: String in HighScoreEntry.PAD_MODELS:
		assert_not_null(models.model_by_name(file_name), file_name)
		assert_not_null(models.mesh_by_name(file_name), file_name)
	var turtle := ModelAnimationPlayer.new(models.model_by_name(HighScoreScene.TURTLE_MODEL))
	assert_eq(turtle.action_error(HighScoreSceneView.TURTLE_ACTION), "", "turtle flipbook action 0")
	for poly: int in HighScoreScene.TURTLE_ANIMATED_POLYS:
		assert_true(turtle.set_animated_poly_cel(poly, HighScoreScene.turtle_cel(0)), "turtle animated poly %d" % poly)
	assert_not_null(models.entry_frog, "GENM_FROG.XMR")
	var hop: int = models.entry_frog_actions.get(HighScoreEntryScene.ACTION_HOP, -1)
	var sit: int = models.entry_frog_actions.get(HighScoreEntryScene.ACTION_SIT, -1)
	assert_eq(hop, 0, "gnm_frog.h GENM_FROG_HOP")
	assert_eq(sit, 1, "gnm_frog.h GENM_FROG_SIT")
	var frog := ModelAnimationPlayer.new(models.entry_frog)
	for action_name: StringName in [HighScoreEntryScene.ACTION_SIT, HighScoreEntryScene.ACTION_HOP]:
		var action: int = models.entry_frog_actions[action_name]
		assert_eq(frog.action_error(action), "", str(action_name))
		assert_gt(frog.action_frame_count(action), 0, str(action_name))
	var pieces: ModelPolyPieces = ModelPolyPieces.build(models.entry_frog.static_models[0], models.entry_frog_library, models.entry_frog_bank)
	assert_gt(pieces.pieces.size(), 0, "the entry frog pops into pieces")
	assert_eq(pieces.missing_image_ids, PackedInt32Array())


func test_name_entry_page_places_the_grid_flips_initials_and_pops_the_frog() -> void:
	var models: OptionsModels = _models()
	if models == null or not models.error.is_empty():
		fail_test("options models: %s" % (models.error if models != null else "no data"))
		return
	var view: HighScoreEntryView = HighScoreEntryView.create(FrontEndAssets.new(), MenuWater.create(), HighScoreEntry.create(true, false), models)
	add_child_autofree(view)
	assert_true(view.flipbook_frog, "the flipbook GENM_FROG is drawn")
	var instances: Array[AnimatedModelInstance] = view.model_instances()
	assert_eq(instances.size(), HighScoreEntry.PAD_COUNT + HighScoreEntry.INITIALS_COUNT + HighScoreEntry.EXTRA_MODELS.size() + 1)
	var frog: AnimatedModelInstance = instances[instances.size() - 1]
	assert_eq(frog.player.action_index, view.frog_action_index(HighScoreEntryScene.ACTION_SIT))
	view.tick(HighScoreEntry.Buttons.FIRE)
	view.render(1.0)
	for index: int in HighScoreEntry.PAD_COUNT:
		assert_eq(instances[index].transform, GameSpace.transform(view.scene.pads[index]), "pad %d" % index)
	for _tick: int in 6:
		view.tick(0)
	var initial: AnimatedModelInstance = view.model_instances()[HighScoreEntry.PAD_COUNT]
	assert_eq(initial.model_mesh, models.mesh_by_name("HI_O.XMR"), "the first initials pad shows O after its flip")
	view.tick(HighScoreEntry.Buttons.RIGHT)
	assert_eq(frog.player.action_index, view.frog_action_index(HighScoreEntryScene.ACTION_HOP))
	for _tick: int in HighScoreEntry.FROG_JUMP_TIME:
		view.tick(0)
	assert_eq(frog.player.action_index, view.frog_action_index(HighScoreEntryScene.ACTION_SIT))
	for direction: int in [HighScoreEntry.Buttons.DOWN, HighScoreEntry.Buttons.DOWN, HighScoreEntry.Buttons.RIGHT,
			HighScoreEntry.Buttons.RIGHT, HighScoreEntry.Buttons.RIGHT, HighScoreEntry.Buttons.RIGHT]:
		view.tick(direction)
		for _tick: int in HighScoreEntry.FROG_JUMP_TIME:
			view.tick(0)
	assert_eq(view.entry.cell, HighScoreEntry.PAD_END)
	view.tick(HighScoreEntry.Buttons.FIRE)
	view.render(1.0)
	assert_false(frog.visible, "END hides the frog")
	assert_gt(view.pop_pieces().size(), 0, "and pops it")
	for _tick: int in HighScoreEntry.POP_DURATION:
		view.tick(0)
	assert_true(view.entry.finished)
	assert_eq(view.pop_pieces().size(), 0)


func test_scrolly_table_shows_ranks_initials_scores_and_the_hopping_frog() -> void:
	var models: OptionsModels = _models()
	if models == null or not models.error.is_empty():
		fail_test("options models: %s" % (models.error if models != null else "no data"))
		return
	var rows: Array[HighScoreRow] = []
	for rank: int in HighScoreBoard.MAIN_COUNT:
		rows.append(HighScoreRow.create("AB.", 250000 - rank * 1000))
	var scene: HighScoreScene = HighScoreScene.create(rows)
	var view: HighScoreSceneView = HighScoreSceneView.create_for(scene, models)
	add_child_autofree(view)
	var water: MenuWater = MenuWater.create()
	var instances: Array[AnimatedModelInstance] = view.model_instances()
	assert_eq(instances.size(), 10 + 30 + 10 + HighScoreScene.EXTRA_MODELS.size() + 1)
	assert_eq(view.pads[2].model_mesh, models.mesh_by_name("HI_DOT.XMR"))
	var pose: ModelPose = view.logs[0].player.sample_pose()
	var cels: PackedInt32Array = HighScoreScene.log_poly_cels(rows[0].score)
	assert_eq(pose.texture_entries[0][OptionsScene.LOG_POLY_INDICES[2]], cels[OptionsScene.LOG_POLY_INDICES[2]], "rank 1 log digit 3")
	assert_eq(view.turtles[3].player.sample_pose().texture_entries[0][0], HighScoreScene.turtle_cel(3))
	var hopped: bool = false
	for _tick: int in HighScoreScene.FROG_WAIT_TIME + 2:
		water.advance()
		hopped = scene.tick(water, true).has(HighScoreTour.EventKind.HOP) or hopped
		view.step()
	view.draw(1.0, MenuWaterView.MAIN_SOURCE, MenuWaterView.MAIN_TARGET)
	assert_true(hopped, "the frog hops up the turtles")
	assert_true(view.frog.visible)
	assert_eq(view.frog.player.action_index, OptionsScene.action_index(HighScoreScene.ACTION_HOP))
	assert_eq(view.turtles[0].transform, GameSpace.transform(scene.turtles[0]) * HighScoreSceneView.turtle_turn())
