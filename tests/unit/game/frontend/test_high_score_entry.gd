extends GutTest
## The name-entry tick machine and its water placement against HighScoreInputStartup,
## HighScoreInputUpdate and HSInputUpdateFrog (hsinput.c:178-545, 1313-1608).

const UP: int = HighScoreEntry.Buttons.UP
const DOWN: int = HighScoreEntry.Buttons.DOWN
const LEFT: int = HighScoreEntry.Buttons.LEFT
const RIGHT: int = HighScoreEntry.Buttons.RIGHT
const FIRE: int = HighScoreEntry.Buttons.FIRE
const HOP_PERIOD: int = HighScoreEntry.FROG_JUMP_TIME + 1
const FLIP_TICKS: int = 8


func _entry() -> HighScoreEntry:
	return HighScoreEntry.create(true, false)


func _run(entry: HighScoreEntry, ticks: int, buttons: int = 0) -> Array[int]:
	var events: Array[int] = []
	for _tick: int in ticks:
		events.append_array(entry.tick(buttons))
	return events


func _hop(entry: HighScoreEntry, buttons: int) -> void:
	_run(entry, HOP_PERIOD, buttons)


func _enter(entry: HighScoreEntry) -> Array[int]:
	var events: Array[int] = entry.tick(FIRE)
	_run(entry, FLIP_TICKS - 1)
	return events


func test_bails_request_the_main_menu_at_startup() -> void:
	var quit: HighScoreEntry = HighScoreEntry.create(true, true)
	assert_eq(PackedInt32Array(quit.startup_events()), PackedInt32Array([HighScoreEntry.EventKind.GAME_QUIT]))
	assert_eq(quit.request, HighScoreEntry.Request.MAIN_MENU)
	var none: HighScoreEntry = HighScoreEntry.create(false, false)
	assert_eq(PackedInt32Array(none.startup_events()), PackedInt32Array([HighScoreEntry.EventKind.NO_HIGH_SCORE]))
	assert_true(none.finished)
	assert_eq(PackedInt32Array(none.tick(RIGHT | FIRE)), PackedInt32Array([]), "the update never runs")
	assert_eq(none.cell, 14)
	assert_eq(none.initials, "   ")
	assert_eq(PackedInt32Array(HighScoreEntry.create(false, true).startup_events()), PackedInt32Array([HighScoreEntry.EventKind.GAME_QUIT]),
		"the quit test comes first")


func test_starts_on_o_facing_east_with_blank_initials() -> void:
	var entry: HighScoreEntry = _entry()
	assert_eq(PackedInt32Array(entry.startup_events()), PackedInt32Array([]))
	assert_eq(entry.cell, 14)
	assert_eq(HighScoreEntry.pad_character(entry.cell), "O")
	assert_eq(entry.facing, HighScoreEntry.Facing.EAST)
	assert_eq(entry.mode, HighScoreEntry.Mode.ACTIVE)
	assert_eq(entry.initials, "   ")
	assert_eq(entry.pad_letter, PackedInt32Array([-1, -1, -1]))
	assert_eq(entry.request, HighScoreEntry.Request.NONE)


func test_layout_helpers() -> void:
	assert_eq(HighScoreEntry.pad_position(0), Vector3i(-0x480, 0, 0x300))
	assert_eq(HighScoreEntry.pad_position(29), Vector3i(0x480, 0, 0x100))
	assert_eq(HighScoreEntry.initials_pad_position(2), Vector3i(0x100, 0, -0x80))
	assert_eq(HighScoreEntry.initials_pad_position(0, 3), Vector3i(-0x100, 0, -0x380))
	assert_eq(HighScoreEntry.model_name(26), "HI_DOT.XMR")
	assert_eq(HighScoreEntry.model_name(HighScoreEntry.PAD_SPACE), HighScoreEntry.BLANK_MODEL)
	assert_eq(HighScoreEntry.model_name(HighScoreEntry.BLANK_PAD), HighScoreEntry.BLANK_MODEL)
	assert_eq(HighScoreEntry.pad_character(HighScoreEntry.PAD_RUB), "")
	assert_eq(HighScoreEntry.pad_character(HighScoreEntry.PAD_SPACE), " ")


func test_held_direction_hops_every_seven_ticks() -> void:
	var entry: HighScoreEntry = _entry()
	assert_eq(PackedInt32Array(entry.tick(RIGHT)), PackedInt32Array([HighScoreEntry.EventKind.HOP]))
	assert_eq(entry.cell, 15, "the grid moves on take-off")
	assert_eq(entry.mode, HighScoreEntry.Mode.JUMPING)
	assert_eq(entry.jump_count, HighScoreEntry.FROG_JUMP_TIME)
	var lifts := PackedInt32Array()
	for _tick: int in HighScoreEntry.FROG_JUMP_TIME - 1:
		assert_eq(PackedInt32Array(entry.tick(LEFT | FIRE)), PackedInt32Array([]), "input is ignored mid-hop")
		lifts.append(entry.jump_lift)
	assert_eq(lifts, PackedInt32Array([0, -40, -64, -72, -64]))
	assert_eq(PackedInt32Array(entry.tick(RIGHT)), PackedInt32Array([HighScoreEntry.EventKind.SPLASH]))
	assert_eq(entry.jump_lift, 0)
	assert_eq(PackedInt32Array(entry.tick(RIGHT)), PackedInt32Array([HighScoreEntry.EventKind.HOP]))
	assert_eq(entry.cell, 16)


func test_up_beats_down_and_blocked_directions_fall_through() -> void:
	var entry: HighScoreEntry = _entry()
	entry.tick(UP | DOWN)
	assert_eq(entry.cell, 4, "Up is tested first")
	assert_eq(entry.facing, HighScoreEntry.Facing.NORTH)
	_run(entry, HighScoreEntry.FROG_JUMP_TIME)
	assert_eq(PackedInt32Array(entry.tick(UP | DOWN)), PackedInt32Array([HighScoreEntry.EventKind.HOP]), "Up at the top row falls to Down")
	assert_eq(entry.cell, 14)
	_run(entry, HighScoreEntry.FROG_JUMP_TIME)
	_hop(entry, UP)
	assert_eq(PackedInt32Array(entry.tick(UP | FIRE)), PackedInt32Array([HighScoreEntry.EventKind.LETTER]), "fire is read past a blocked Up")
	assert_eq(entry.initials, "E  ")


func test_occupied_pad_refuses_the_hop_and_the_fire() -> void:
	var entry: HighScoreEntry = _entry()
	entry.set_blocked_cells(PackedInt32Array([4]))
	assert_eq(PackedInt32Array(entry.tick(UP | FIRE)), PackedInt32Array([]))
	assert_eq(entry.cell, 14)
	assert_eq(entry.facing, HighScoreEntry.Facing.NORTH, "the frog still turns")
	assert_eq(entry.mode, HighScoreEntry.Mode.ACTIVE)
	assert_eq(entry.position, 0, "fire is not read on a refused hop")
	assert_eq(PackedInt32Array(entry.tick(FIRE)), PackedInt32Array([HighScoreEntry.EventKind.LETTER]))


func test_letter_flips_the_next_initials_pad() -> void:
	var entry: HighScoreEntry = _entry()
	assert_eq(PackedInt32Array(entry.tick(FIRE)), PackedInt32Array([HighScoreEntry.EventKind.LETTER]))
	assert_eq(entry.initials, "O  ")
	assert_eq(entry.position, 1)
	assert_true(entry.pad_flipping(0))
	var angles := PackedInt32Array([entry.pad_angle[0]])
	var turns := PackedInt32Array([entry.pad_turn[0]])
	var letters := PackedInt32Array([entry.pad_letter[0]])
	for _tick: int in FLIP_TICKS - 1:
		assert_eq(PackedInt32Array(entry.tick(FIRE)), PackedInt32Array([]), "fire waits for the flip")
		angles.append(entry.pad_angle[0])
		turns.append(entry.pad_turn[0])
		letters.append(entry.pad_letter[0])
	assert_eq(angles, PackedInt32Array([0x100, 0x200, 0x300, 0x400, -0x300, -0x200, -0x100, 0]))
	assert_eq(turns, PackedInt32Array([0, 0x100, 0x200, 0x300, 0x400, -0x300, -0x200, -0x100]))
	assert_eq(letters, PackedInt32Array([-1, -1, -1, -1, 14, 14, 14, 14]), "the model swaps at 0x500")
	assert_false(entry.pad_flipping(0))
	assert_eq(PackedInt32Array(entry.tick(FIRE)), PackedInt32Array([HighScoreEntry.EventKind.LETTER]))
	assert_eq(entry.initials, "OO ")
	assert_true(entry.pad_flipping(1))
	assert_eq(entry.pad_turn, PackedInt32Array([0, 0, 0]))


func test_fourth_letter_is_ignored_silently() -> void:
	var entry: HighScoreEntry = _entry()
	for _letter: int in 3:
		_enter(entry)
	assert_eq(entry.initials, "OOO")
	assert_eq(PackedInt32Array(entry.tick(FIRE)), PackedInt32Array([]))
	assert_eq(entry.position, 3)
	assert_false(entry.pad_flipping(0) or entry.pad_flipping(1) or entry.pad_flipping(2))
	assert_eq(entry.mode, HighScoreEntry.Mode.ACTIVE, "END is not selected automatically")


func test_back_rubs_out_the_last_letter() -> void:
	var entry: HighScoreEntry = _entry()
	_enter(entry)
	_hop(entry, DOWN)
	for _step: int in 4:
		_hop(entry, RIGHT)
	assert_eq(entry.cell, HighScoreEntry.PAD_RUB)
	assert_eq(PackedInt32Array(_enter(entry)), PackedInt32Array([HighScoreEntry.EventKind.RUB]))
	assert_eq(entry.initials, "   ")
	assert_eq(entry.position, 0)
	assert_eq(entry.pad_letter, PackedInt32Array([-1, -1, -1]), "the pad flips back to blank")
	assert_eq(PackedInt32Array(entry.tick(FIRE)), PackedInt32Array([]), "BACK with nothing entered does nothing")
	assert_false(entry.pad_flipping(0))


func test_end_pops_the_frog_and_requests_the_view() -> void:
	var entry: HighScoreEntry = _entry()
	_enter(entry)
	_hop(entry, DOWN)
	for _step: int in 5:
		_hop(entry, RIGHT)
	assert_eq(entry.cell, HighScoreEntry.PAD_END)
	assert_eq(PackedInt32Array(entry.tick(FIRE)), PackedInt32Array([HighScoreEntry.EventKind.END]))
	assert_eq(entry.mode, HighScoreEntry.Mode.STUNNED)
	assert_eq(entry.pop_timer, HighScoreEntry.POP_DURATION - 1, "the pop updates on the END tick")
	assert_eq(PackedInt32Array(_run(entry, HighScoreEntry.POP_DURATION - 2, UP | FIRE)), PackedInt32Array([]))
	assert_eq(entry.pop_timer, 1)
	assert_eq(entry.request, HighScoreEntry.Request.NONE)
	assert_eq(PackedInt32Array(entry.tick(0)), PackedInt32Array([HighScoreEntry.EventKind.ENTERED]))
	assert_eq(entry.request, HighScoreEntry.Request.VIEW)
	assert_eq(entry.initials, "O  ")
	assert_eq(PackedInt32Array(entry.tick(FIRE)), PackedInt32Array([]))


func test_scene_sets_models_on_the_water() -> void:
	var entry: HighScoreEntry = _entry()
	var scene: HighScoreEntryScene = HighScoreEntryScene.create(entry)
	assert_eq(scene.pads.size(), HighScoreEntry.PAD_COUNT)
	assert_eq(scene.initials.size(), HighScoreEntry.INITIALS_COUNT)
	assert_eq(scene.extras.size(), HighScoreEntry.EXTRA_MODELS.size())
	var events: Array[int] = entry.tick(FIRE)
	scene.step(entry, events, 7)
	for index: int in [0, 14, 29]:
		var pad: PackedInt32Array = scene.pads[index]
		var at: Vector3i = HighScoreEntry.pad_position(index)
		assert_eq(Vector3i(pad[9], pad[10], pad[11]), Vector3i(at.x, OptionsScene.surface_height(at.x, at.z, 7), at.z))
	var initial: PackedInt32Array = scene.initials[0]
	assert_eq(initial.slice(0, 9), PackedInt32Array([0x1300, 0, 0, 0, 0x1300, 0, 0, 0, 0x1300]), "no turn on the fire tick")
	assert_eq(initial[10], OptionsScene.surface_height(initial[9], initial[11], 7))
	events = entry.tick(0)
	scene.step(entry, events, 8)
	var turned: PackedInt32Array = OptionsScene.multiply(HighScoreEntryScene.turn_z(0x100), OptionsScene.diagonal(0x1300, 0x1300, 0x1300))
	assert_eq(scene.initials[0].slice(0, 9), turned)
	var frog_rotation: PackedInt32Array = OptionsScene.multiply(HighScoreEntryScene.turn_y(HighScoreEntry.Facing.EAST),
		OptionsScene.multiply(OptionsScene.diagonal(0x1400, 0x1400, 0x1400), scene.pads[14]))
	assert_eq(scene.frog.slice(0, 9), frog_rotation.slice(0, 9))
	assert_eq(scene.frog[10], scene.pads[14][10])


func test_scene_hops_the_frog_between_pads() -> void:
	var entry: HighScoreEntry = _entry()
	var scene: HighScoreEntryScene = HighScoreEntryScene.create(entry)
	scene.step(entry, entry.tick(0), 0)
	scene.step(entry, entry.tick(RIGHT), 1)
	assert_eq(scene.frog_action, HighScoreEntryScene.ACTION_HOP)
	assert_true(scene.frog_action_set)
	var lowest: int = 0
	for frame: int in range(2, 2 + HighScoreEntry.FROG_JUMP_TIME):
		scene.step(entry, entry.tick(0), frame)
		lowest = mini(lowest, scene.frog[10] - scene.pads[15][10])
	assert_lt(lowest, -20, "the frog rises above the pads mid-hop")
	assert_eq(scene.splashes, PackedInt32Array([15]))
	assert_eq(scene.frog_action, HighScoreEntryScene.ACTION_SIT)
	var pad: PackedInt32Array = scene.pads[15]
	assert_eq(Vector3i(scene.frog[9], scene.frog[10], scene.frog[11]), Vector3i(pad[9], pad[10], pad[11]))
	assert_eq(scene.shadow_phase, 0)


func test_scene_hides_the_frog_on_end() -> void:
	var entry: HighScoreEntry = _entry()
	var scene: HighScoreEntryScene = HighScoreEntryScene.create(entry)
	var frame: int = 0
	for buttons: int in [DOWN, RIGHT, RIGHT, RIGHT, RIGHT, RIGHT]:
		for _tick: int in HOP_PERIOD:
			scene.step(entry, entry.tick(buttons), frame)
			frame += 1
	assert_eq(entry.cell, HighScoreEntry.PAD_END)
	scene.step(entry, entry.tick(FIRE), frame)
	assert_false(scene.frog_visible)
	assert_false(scene.shadow_visible)
	assert_true(scene.explosion)
	scene.step(entry, entry.tick(0), frame + 1)
	assert_false(scene.explosion)
