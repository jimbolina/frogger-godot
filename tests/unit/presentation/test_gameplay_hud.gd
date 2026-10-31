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
