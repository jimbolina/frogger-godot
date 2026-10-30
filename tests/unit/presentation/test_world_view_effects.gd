extends GutTest
## The world view starts, steps and stops effects from committed states and tick events only.

var _view: GameplayWorldView

func before_each() -> void:
	_view = GameplayWorldView.new()
	add_child_autofree(_view)
	_view.build_world()
	var scene := MapSceneData.new()
	scene.effects = EffectResources.resolve(null, null, null, null, null)
	_view._configure_effects(scene)
	_view.accept_state(_state(0))

func _state(tick: int, collected: int = 0) -> GameplayState:
	var state := GameplayState.new()
	state.tick_index = tick
	state.entity_environment = EntityEnvironmentState.new()
	state.entity_environment.collected = collected
	state.frog.velocity_16 = Vector3i(65536, 0, 0)
	return state

func _event(kind: TickEvent.Kind) -> TickEvent:
	return TickEvent.make(kind)

func _kinds() -> Array[ParticleField.Kind]:
	var result: Array[ParticleField.Kind] = []
	for field: ParticleField in _view.effect_fields():
		result.append(field.kind)
	return result

func test_hops_start_the_trail_on_the_jump_tick() -> void:
	_view.accept_state(_state(1), [_event(TickEvent.Kind.HOP)])
	assert_eq(_view.effect_trail().timer, HopTrailState.HOP_TIMER - 1)
	_view.accept_state(_state(2), [_event(TickEvent.Kind.SUPER_HOP)])
	assert_eq(_view.effect_trail().timer, HopTrailState.SUPERJUMP_TIMER - 1)
	_view.accept_state(_state(2), [_event(TickEvent.Kind.HOP)])
	assert_eq(_view.effect_trail().timer, HopTrailState.SUPERJUMP_TIMER - 1, "a repeated tick does not step")

func test_slide_death_splash_and_reset_follow_the_frog_particle_slot() -> void:
	_view.accept_state(_state(1), [_event(TickEvent.Kind.SLIDE_PARTICLES_REQUEST)])
	assert_eq(_kinds(), [ParticleField.Kind.FROG_SLIDE])
	_view.accept_state(_state(2), [_event(TickEvent.Kind.SLIDE_PARTICLES_REQUEST)])
	assert_eq(_view.effect_fields().size(), 1, "one frog generator at a time")
	var dying: GameplayState = _state(3)
	dying.frog.death_equate = FrogAnimationCatalog.DROWN
	_view.accept_state(dying, [TickEvent.death_animation(FrogAnimationCatalog.DROWN), TickEvent.splash(Vector3i(0, 0, 0))])
	assert_eq(_kinds(), [ParticleField.Kind.FROG_BUBBLE], "the death kills the slip, then the drowning splash bubbles")
	assert_eq(_view.effect_rings().size(), 1)
	assert_eq(_view.effect_rings()[0].life, PopRingGeometry.DURATION - 1)
	assert_eq(_view.effect_rings()[0].colour, ExeParticleGenerators.C_POP_COLOURS[0])
	assert_eq(_view.effect_splashes().size(), 1)
	_view.accept_state(_state(4), [TickEvent.transition(LevelFlowState.Phase.PLAY)])
	assert_eq(_view.effect_fields().size(), 0, "the frog reset kills the bubbles")
	assert_false(_view.effect_trail().drawn())
	assert_eq(_view.effect_rings().size(), 1, "the ring runs out on its own")

func test_entity_splashes_do_not_bubble_and_fire_waits_for_reset() -> void:
	var dying: GameplayState = _state(1)
	dying.frog.death_equate = FrogAnimationCatalog.DROWN
	_view.accept_state(dying, [TickEvent.splash(Vector3i(5, 0, 5)).for_entity(3)])
	assert_eq(_view.effect_fields().size(), 0)
	assert_eq(_view.effect_splashes().size(), 1)
	_view.accept_state(_state(2), [_event(TickEvent.Kind.DEATH_FIRE_PARTICLE_REQUEST), TickEvent.death_animation(FrogAnimationCatalog.DROWN)])
	assert_eq(_kinds(), [ParticleField.Kind.FROG_FIRE])
	for tick: int in range(3, 40):
		_view.accept_state(_state(tick), [])
	assert_eq(_kinds(), [ParticleField.Kind.FROG_FIRE], "fire is infinite")
	assert_eq(_view.effect_rings().size(), 0, "the ring lasts 30 updates")
	assert_eq(_view.effect_splashes().size(), 0, "the splash is killed at update 23")

func test_checkpoints_kill_particles_and_fresh_runs_collapse_effects() -> void:
	_view.accept_state(_state(1), [_event(TickEvent.Kind.SLIDE_PARTICLES_REQUEST), TickEvent.death_animation(2)])
	assert_eq(_view.effect_fields().size(), 0, "the slip dies with the frog in the same tick")
	_view.accept_state(_state(2), [_event(TickEvent.Kind.SLIDE_PARTICLES_REQUEST)])
	_view.accept_state(_state(3, 1))
	assert_eq(_view.effect_fields().size(), 0, "collecting a checkpoint kills the frog generator")
	_view.accept_state(_state(4), [_event(TickEvent.Kind.HOP), TickEvent.death_animation(2)])
	var committed: GameplayState = _state(5)
	var copy: GameplayState = committed.copy()
	_view._current = null
	_view.accept_state(committed)
	assert_eq(_view.effect_rings().size(), 0)
	assert_false(_view.effect_trail().drawn())
	assert_eq(committed.frog.matrix12, copy.frog.matrix12)
	assert_eq(committed.frog.velocity_16, copy.frog.velocity_16)
	assert_eq(committed.tick_index, copy.tick_index)
