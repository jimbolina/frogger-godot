extends GutTest
## HUD layout obeys frozen source boundaries without advancing or retaining mutable rules.

func test_spare_lives_use_source_groups() -> void:
	assert_eq(GameplayHud.life_icons(0), Vector2i(0, 0))
	assert_eq(GameplayHud.life_icons(1), Vector2i(0, 0))
	assert_eq(GameplayHud.life_icons(4), Vector2i(0, 3))
	assert_eq(GameplayHud.life_icons(5), Vector2i(1, 1))
	assert_eq(GameplayHud.life_icons(11), Vector2i(3, 1))

func test_gather_delays_then_moves_and_scatter_moves_down() -> void:
	assert_eq(GameplayHud.start_checkpoint_position(0, 6), Vector2(240, 280))
	assert_eq(GameplayHud.start_checkpoint_position(0, 7), Vector2(232, 285))
	assert_eq(GameplayHud.start_checkpoint_position(4, 26), Vector2(400, 280))
	assert_eq(GameplayHud.start_checkpoint_position(4, 56), Vector2(80, 435))
	assert_eq(GameplayHud.start_checkpoint_position(0, 57), Vector2(16, 436))
	assert_eq(GameplayHud.start_checkpoint_position(0, 64), Vector2(16, 438))

func test_presentation_detaches_snapshot_and_never_advances_it() -> void:
	var hud := GameplayHud.new()
	add_child_autofree(hud)
	var state := GameplayState.new()
	state.entity_environment = EntityEnvironmentState.new()
	state.flow.score = 123
	state.entity_environment.collected = 3
	hud.present(state, 12)
	state.flow.score = 999
	state.entity_environment.collected = 31
	assert_eq(hud._state.flow.score, 123)
	assert_eq(hud._state.entity_environment.collected, 3)
	assert_eq(hud._tick, 12)
	hud.queue_redraw()
	assert_eq(state.tick_index, 0)

func test_missing_data_has_actionable_error() -> void:
	assert_string_contains(GameplayHudAssets.from_data(null).error, "valid player data")

func test_hud_images_draw_at_their_records_retail_size() -> void:
	var assets := GameplayHudAssets.new()
	var image := VloImage.new()
	image.padded_width = 16
	image.padded_height = 8
	image.width = 14
	image.height = 6
	assets.images["bonus"] = image
	assets.textures["bonus"] = ImageTexture.create_from_image(Image.create(64, 32, false, Image.FORMAT_RGBA8))
	assert_eq(assets.retail_size("bonus"), Vector2(16, 8))
	assert_eq(assets.texture_scale("bonus"), Vector2(4, 4))
	assert_eq(assets.retail_size("missing"), Vector2.ZERO)
	assert_eq(assets.texture_scale("missing"), Vector2.ONE)

func test_help_is_once_per_run_and_powerups_can_replace_it() -> void:
	var hud := GameplayHud.new()
	add_child_autofree(hud)
	hud._rewards = GameplayRewards.component_definitions()
	var state := GameplayState.new()
	hud.present(state, 0)
	hud.present(state, 1, [TickEvent.make(TickEvent.Kind.SUPER_HOP)])
	assert_eq(hud._help_text, "SUPERHOP")
	assert_eq(hud._help_tick, 1)
	hud.present(state, 70, [TickEvent.make(TickEvent.Kind.SUPER_HOP)])
	assert_eq(hud._help_tick, 1)
	hud.present(state, 71, [TickEvent.reward(23)])
	assert_eq(hud._help_text, "AUTO-HOP")
	assert_eq(hud._help_tick, 71)
	hud.present(state, 0)
	hud.present(state, 1, [TickEvent.make(TickEvent.Kind.SUPER_HOP)])
	assert_eq(hud._help_text, "SUPERHOP")
	hud.clear()
	assert_null(hud._state)
	assert_null(hud.assets)

func test_checkpoint_motion_keeps_source_first_step_and_fixed_point_truncation() -> void:
	assert_eq(GameplayHud.checkpoint_motion(Vector2i(250, -20), Vector2i(250, 215), 30), Vector2(250, -13))
	assert_eq(GameplayHud.checkpoint_motion(Vector2i(250, -20), Vector2i(250, 215), 1), Vector2(250, 214))

func test_newfont_text_keeps_the_retail_placement() -> void:
	var score_baseline: Vector2 = NewfontText.baseline(Vector2(592, 16))
	assert_eq(score_baseline, Vector2(592, 24))
	var score_width: int = NewfontText.width("%8d" % 123)
	assert_eq(score_width, 64)
	var help_left: int = 320 - NewfontText.width("SUPERHOP") / 2
	assert_eq(help_left, 288)

func test_ink_records_text_lines_in_order_without_a_font() -> void:
	var ink := GameplayHudInk.new()
	add_child_autofree(ink)
	ink.configure(CanvasItemMaterial.BLEND_MODE_MIX)
	ink.text(Vector2(592, 16), "1 UP", Color.WHITE)
	ink.text(Vector2(288, 436), "SUPERHOP", Color(0.5, 0.5, 0.5))
	assert_null(ink.font)
	assert_eq(ink.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR, "newfont text is linearly filtered")
	assert_eq(ink.lines.size(), 2)
	var first: GameplayHudInk.Line = ink.lines[0]
	var second: GameplayHudInk.Line = ink.lines[1]
	assert_eq(first.at, Vector2(592, 16))
	assert_eq(first.text, "1 UP")
	assert_eq(first.colour, Color.WHITE)
	assert_eq(second.at, Vector2(288, 436))
	assert_eq(second.text, "SUPERHOP")
	assert_eq(second.colour, Color(0.5, 0.5, 0.5))

func test_help_keeps_fading_on_paused_frames_while_the_tick_holds() -> void:
	var hud := GameplayHud.new()
	add_child_autofree(hud)
	var state := GameplayState.new()
	hud.present(state, 10)
	hud.show_help("CHEAT", true)
	assert_eq(hud._help_text, "CHEAT")
	assert_eq(hud.help_age(), 0)
	for frame: int in 20:
		hud.advance_paused()
	assert_eq(hud._tick, 10, "pausing never advances the committed tick")
	assert_eq(hud.help_age(), 20)
	assert_eq(hud.help_brightness(), 1.0)
	hud.present(state, 11)
	assert_eq(hud.help_age(), 21, "the next tick continues the paused age")
	for frame: int in 30:
		hud.advance_paused()
	assert_almost_eq(hud.help_brightness(), 5.0 / 16.0, 0.0001)
	hud.present(state, 16)
	assert_eq(hud.help_age(), 56)
	assert_eq(hud.help_brightness(), 0.0)

func test_shown_help_obeys_once_and_the_hold() -> void:
	var hud := GameplayHud.new()
	add_child_autofree(hud)
	var state := GameplayState.new()
	hud.present(state, 0)
	hud.show_help("ONCE", true)
	hud.show_help("OTHER", false)
	assert_eq(hud._help_text, "ONCE", "a help text on screen holds out another for 56 frames")
	for frame: int in 56:
		hud.advance_paused()
	hud.show_help("ONCE", true)
	assert_eq(hud.help_age(), 56, "a once-only help text never shows again this run")
	hud.show_help("AGAIN", false)
	assert_eq(hud._help_text, "AGAIN")
	assert_eq(hud.help_age(), 0)
	hud.show_help("OVER", false, true)
	assert_eq(hud._help_text, "OVER", "overwrite replaces a help text on screen")
	for frame: int in 56:
		hud.advance_paused()
	hud.show_help("OVER", false)
	assert_eq(hud._help_text, "OVER")
	assert_eq(hud.help_age(), 0, "a help text shown without once may repeat")
	hud.present(state, 0)
	assert_eq(hud._paused_ticks, 56 * 2, "a repeated tick keeps the paused frames")
	hud.clear()
	assert_eq(hud._paused_ticks, 0)
