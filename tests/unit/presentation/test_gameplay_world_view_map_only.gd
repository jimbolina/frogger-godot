extends GutTest
## The level-complete page shows the map alone: map-only hides the frog, entity models, effect
## views and glow lights while the map stays, extra map ticks keep it animating while the game
## does not tick, and a fresh run or a detach clears both.

var _view: GameplayWorldView


func before_each() -> void:
	_view = GameplayWorldView.new()
	add_child_autofree(_view)
	_view.build_world()
	var assets := TerrainFrogAssets.new()
	assets.model = SyntheticMof.static_file([SyntheticMof.square(MofPolygonType.F4)])
	assets.mesh = ModelMeshBuilder.new(TextureLibrary.new()).build_animated(assets.model)
	assets.player = ModelAnimationPlayer.new(assets.model)
	_view.build_frog(assets)
	var scene := MapSceneData.new()
	scene.map = MapFile.new()
	scene.remap = TextureRemap.new()
	_view.build_map(scene)
	var file: MofFile = SyntheticMof.static_file([SyntheticMof.square(MofPolygonType.F4)])
	_view._entity_models.append(null)
	_view._entity_meshes.append(ModelMeshBuilder.new(TextureLibrary.new()).build_animated(file))
	_view._entity_files.append(file)
	_view._entity_generations.append(-1)
	_view.accept_state(_state(1))
	_view.draw_state(1.0)


func after_each() -> void:
	GraphicsProfile.reset()


func _state(tick: int) -> GameplayState:
	var state := GameplayState.new()
	state.tick_index = tick
	state.entities = EntityRunSnapshot.new()
	state.entities.entities.append(EntitySnapshot.new())
	return state


func _effect_views() -> Array[Node3D]:
	var views: Array[Node3D] = [_view._tongue_view, _view._swarm_view, _view._cave_sprite_view, _view._overlay_view,
		_view._shadow_view, _view._trail_view, _view._particle_view, _view._splash_view, _view._pop_view,
		_view._piece_view, _view._glow_view]
	return views


func _entity_model() -> AnimatedModelInstance:
	return _view._entity_models[0]


func test_map_only_hides_the_frog_entities_effects_and_glow_lights_but_keeps_the_map() -> void:
	assert_not_null(_entity_model())
	assert_true(_view._frog_model.visible)
	assert_true(_entity_model().visible)
	for view: Node3D in _effect_views():
		view.visible = true
	_view._frog.visible = true
	_view.scene_lighting.place_glow_lights([GlowLightSpec.Point.new(Vector3.ZERO, Color.WHITE, 1.0, 2.0)])
	assert_eq(_view.scene_lighting.glow_light_pool().shown_count(), 1)
	_view.set_map_only(true)
	_view.draw_state(1.0)
	assert_true(_view.is_map_only())
	assert_false(_view._frog_model.visible)
	assert_false(_view._frog.visible)
	assert_false(_entity_model().visible)
	for view: Node3D in _effect_views():
		assert_false(view.visible, view.get_class())
	assert_eq(_view.scene_lighting.glow_light_pool().shown_count(), 0)
	assert_true(_view._map_instance.is_visible_in_tree(), "the map stays")
	_view.accept_state(_state(2))
	_view.draw_state(1.0)
	assert_false(_entity_model().visible, "a committed state does not bring the models back")
	assert_false(_view._frog_model.visible)
	_view.set_map_only(false)
	assert_false(_view.is_map_only())
	assert_true(_view._frog.visible, "the marker comes back as it was")
	for view: Node3D in _effect_views():
		assert_true(view.visible, "%s comes back as it was" % view.get_class())
	_view.draw_state(1.0)
	assert_true(_view._frog_model.visible)
	assert_true(_entity_model().visible)


func test_advance_map_tick_steps_the_map_while_the_game_stands_still() -> void:
	assert_eq(_view._map_instance.tick, 0)
	_view.advance_map_tick()
	assert_eq(_view._map_instance.tick, 1)
	_view.advance_map_tick()
	_view.draw_state(1.0)
	assert_eq(_view._map_instance.tick, 2)
	assert_eq(_view.map_extra_ticks(), 2)
	_view.accept_state(_state(2))
	_view.draw_state(1.0)
	assert_eq(_view._map_instance.tick, 3, "the offset holds across committed ticks")


func test_rebuilding_entities_clears_map_only_and_the_map_offset() -> void:
	_view.set_map_only(true)
	_view.advance_map_tick()
	_view.build_entities(null, null, null)
	assert_false(_view.is_map_only())
	assert_eq(_view.map_extra_ticks(), 0)
	assert_eq(_view._map_instance.tick, 1, "the map is not stepped back until the next draw")


func test_a_new_run_and_a_detach_clear_map_only_and_the_map_offset() -> void:
	var screen := GameplayScreen.new()
	screen.auto_open = false
	add_child_autofree(screen)
	screen.set_process(false)
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(screen.open_run(scenario.level, scenario.initial), "")
	screen.draw_state(1.0)
	screen._shadow_view.visible = true
	screen.set_map_only(true)
	screen.advance_map_tick()
	assert_false(screen._shadow_view.visible)
	assert_eq(screen.map_extra_ticks(), 1)
	assert_eq(screen.open_run(scenario.level, scenario.initial), "")
	assert_false(screen.is_map_only())
	assert_eq(screen.map_extra_ticks(), 0)
	screen.set_map_only(true)
	screen.advance_map_tick()
	screen.close_data()
	assert_false(screen.is_map_only())
	assert_eq(screen.map_extra_ticks(), 0)
