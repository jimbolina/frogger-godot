extends GutTest
## The scrolly high-score set against HSInitialiseScrollyHighScore, HSUpdateScrollyHighScores,
## HSUpdateFrog and HSUpdateFlying (HSView.c:2283-2993).

var _water: MenuWater = null


func _scene() -> HighScoreScene:
	_water = MenuWater.create(0)
	var rows: Array[HighScoreRow] = [HighScoreRow.create("T.M", 250000), HighScoreRow.create("M[B", 7),
		HighScoreRow.create("A Z", 0)]
	return HighScoreScene.create(rows)


func _run(scene: HighScoreScene, ticks: int, scrolly: bool = true) -> Array[int]:
	var events: Array[int] = []
	for _tick: int in ticks:
		events.append_array(scene.tick(_water, scrolly))
		_water.advance()
	return events


func test_layout_puts_rank_one_at_the_top() -> void:
	var scene: HighScoreScene = _scene()
	assert_eq(scene.turtles.size(), 10)
	assert_eq(scene.pads.size(), 30)
	assert_eq(scene.logs.size(), 10)
	assert_eq(scene.extras.size(), 5)
	assert_eq(scene.turtles[0][9], -0x480)
	assert_eq(scene.turtles[0][11], -0x480)
	assert_eq(scene.turtles[9][11], 0x480)
	assert_eq(HighScoreScene.turtle_cel(0), 9, "the nearest turtle reads 10")
	assert_eq(scene.pads[0][9], -0x300)
	assert_eq(scene.pads[2][9], -0x100)
	assert_eq(scene.pads[0][11], 0x480, "rank 1 is the far row")
	assert_eq(scene.logs[0][9], 0x280)
	assert_eq(scene.logs[0][11], 0x480)
	assert_eq(scene.logs[9][11], -0x480)
	for matrix: PackedInt32Array in scene.turtles:
		assert_eq(matrix[10], OptionsMenu.FLY_ON_HEIGHT)


func test_pad_letters_and_log_digits() -> void:
	var scene: HighScoreScene = _scene()
	assert_eq(scene.pad_letters.slice(0, 9), PackedInt32Array([19, 26, 12, 12, 26, 1, 0, 27, 25]))
	assert_eq(scene.pad_letters[9], HighScoreScene.BLANK_LETTER, "missing rows are blank")
	assert_eq(scene.log_digits[0], PackedInt32Array([10, 10, 2, 5, 0, 0, 0, 0]))
	assert_eq(scene.log_digits[1], PackedInt32Array([10, 10, 10, 10, 10, 10, 10, 7]))
	assert_eq(scene.log_digits[2], PackedInt32Array([10, 10, 10, 10, 10, 10, 10, 0]), "the last digit always shows")
	assert_eq(HighScoreScene.letter_index("^"), 29)
	assert_eq(HighScoreScene.letter_index("a"), HighScoreScene.BLANK_LETTER)
	var polys: PackedInt32Array = HighScoreScene.log_poly_cels(25000)
	assert_eq(polys[56], 10, "first digit polys start at 56")
	assert_eq(polys[0], 0, "last digit polys start at 0")
	assert_eq(polys[16 + 7], 5, "the fifth digit's polys start at 16")


func test_models_fly_on_then_ride_the_water() -> void:
	var scene: HighScoreScene = _scene()
	_run(scene, 1)
	assert_eq(scene.fly_on, 9)
	assert_eq(scene.extras[0][10], mini(OptionsMenu.FLY_ON_HEIGHT + OptionsMenu.FLY_ON_SPEED,
		OptionsScene.surface_height(-0x400, -0x580, 0)))
	_run(scene, 9)
	assert_eq(scene.fly_on, 0)
	assert_eq(scene.extras[0][10], OptionsScene.surface_height(-0x400, -0x580, 9))
	assert_true(scene.shadow_visible)


func test_static_camera_hides_and_holds_the_frog() -> void:
	var scene: HighScoreScene = _scene()
	var before: Vector3i = scene.frog_position
	assert_eq(_run(scene, 40, false), [] as Array[int])
	assert_false(scene.frog_visible)
	assert_eq(scene.frog_position, before)
	assert_eq(scene.frog_count, HighScoreScene.FROG_WAIT_TIME)
	assert_false(scene.camera_followed)


func test_frog_waits_hops_and_splashes() -> void:
	var scene: HighScoreScene = _scene()
	assert_eq(_run(scene, HighScoreScene.FROG_WAIT_TIME - 1), [] as Array[int])
	assert_eq(_run(scene, 1), [HighScoreTour.EventKind.HOP] as Array[int])
	assert_eq(scene.frog_turtle, 1)
	assert_true(scene.frog_jumping)
	assert_eq(scene.frog_action, OptionsScene.action_index(HighScoreScene.ACTION_HOP))
	assert_eq(_run(scene, HighScoreScene.FROG_JUMP_TIME - 1), [] as Array[int])
	assert_eq(_run(scene, 1), [HighScoreTour.EventKind.SPLASH] as Array[int])
	assert_eq(scene.splashes, PackedInt32Array([1]))
	assert_eq(scene.frog[11], scene.turtles[1][11])
	assert_eq(scene.frog[10], scene.turtles[1][10] + HighScoreScene.FROG_RAISE)
	assert_eq(scene.frog_action, OptionsScene.action_index(HighScoreScene.ACTION_WAIT1))


func test_frog_turns_at_the_top_turtle() -> void:
	var scene: HighScoreScene = _scene()
	var cycle: int = HighScoreScene.FROG_WAIT_TIME + HighScoreScene.FROG_JUMP_TIME
	_run(scene, cycle * 9)
	assert_eq(scene.frog_turtle, 9)
	assert_eq(scene.frog_direction, HighScoreScene.Direction.NORTH)
	_run(scene, HighScoreScene.FROG_WAIT_TIME)
	assert_eq(scene.frog_turtle, 8)
	assert_eq(scene.frog_direction, HighScoreScene.Direction.SOUTH)


func test_camera_follows_once_flying_has_ended() -> void:
	var scene: HighScoreScene = _scene()
	_run(scene, 10)
	assert_false(scene.camera_followed, "the counter was still 1 before this tick's decrement")
	_run(scene, 1)
	assert_true(scene.camera_followed)
	var follow: int = -0x480 + HighScoreScene.CAMERA_FOLLOW_OFFSET
	assert_eq(scene.camera_source_z, follow + HighScoreScene.MAIN_CAMERA_SOURCE.z)
	assert_eq(scene.camera_target_z, follow + HighScoreScene.MAIN_CAMERA_TARGET.z)


func test_fly_off_slides_away_and_leaves() -> void:
	var scene: HighScoreScene = _scene()
	_run(scene, 12)
	scene.start_fly_off()
	var left: int = scene.pads[0][9]
	var right: int = scene.logs[0][9]
	var frog_x: int = scene.frog[9]
	assert_false(_run(scene, 9).has(HighScoreTour.EventKind.LEAVE))
	assert_eq(scene.pads[0][9], left - 9 * OptionsMenu.FLY_OFF_SPEED)
	assert_eq(scene.logs[0][9], right + 9 * OptionsMenu.FLY_OFF_SPEED)
	assert_true(scene.frog[9] <= frog_x - 9 * OptionsMenu.FLY_OFF_SPEED, "the frog slides with its turtle")
	assert_false(scene.camera_followed)
	assert_eq(_run(scene, 1), [HighScoreTour.EventKind.LEAVE] as Array[int])
	assert_eq(scene.fly_off, 0)


func test_log_transform_scales_and_tilts() -> void:
	var transform: PackedInt32Array = HighScoreScene.log_transform()
	assert_eq(transform[0], HighScoreScene.LOG_SCALE_X)
	assert_eq(transform[4], (HighScoreScene.MODEL_SCALE * StackLayout.rcos(HighScoreScene.LOG_TILT)) >> 12)
	assert_eq(transform[5], (HighScoreScene.MODEL_SCALE * -StackLayout.rsin(HighScoreScene.LOG_TILT)) >> 12)
