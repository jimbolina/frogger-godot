extends GutTest
## Aggregate pickup voice ownership, conditional pitch RNG and reset rollback.

class RejectFinal extends TickGuard:
	func check(phase: Phase, _candidate: TickGuardCandidate) -> String:
		return "pickup sound rejected" if phase == Phase.FINAL else ""

func _level() -> LevelDefinition:
	var level := LevelDefinition.new()
	level.grid = GridDefinition.new()
	level.grid.dimensions = Vector2i.ONE
	var stack := GridStackDefinition.new()
	stack.square_count = 1
	level.grid.stacks.append(stack)
	var square := GridSquareDefinition.new()
	square.flags = GridSquareFlags.USABLE | GridSquareFlags.SAFE
	square.vertices.assign([Vector3i(0, 0, 256), Vector3i(256, 0, 256), Vector3i.ZERO, Vector3i(256, 0, 0)])
	level.grid.squares.append(square)
	level.collision_enabled = true
	var collision := EntityCollisionDefinition.new()
	collision.group_dimensions = Vector2i.ONE
	collision.group_size = Vector2i(1024, 1024)
	collision.environment = EntityEnvironmentState.new()
	collision.environment.checkpoint_positions.resize(5)
	var entity := EntityDefinition.new()
	entity.entity_index = 0
	entity.behavior = EntityBehaviorCatalog.resolve("BONUS_FLY")
	entity.behavior.execution = EntityBehavior.Execution.CONTACT
	entity.form_flags = 8 | 16
	entity.matrix12[9] = 128
	entity.matrix12[11] = 128
	var contact := FormContactDefinition.new()
	contact.entity_index = 0
	contact.form_id = 0
	contact.form_grid_id = 0
	contact.has_form_data = false
	collision.entities.append(entity)
	collision.contacts.append(contact)
	level.entity_collision = collision
	var sample := LogicalSoundDefinition.new()
	sample.sound_id = 21
	sample.flags = LogicalSoundDefinition.LOOPED
	sample.pitch_mod = 60
	sample.frame_count = 1000
	level.sounds.append(sample)
	return level

func test_pickup_voice_and_two_pitch_draws_commit_and_roll_back_together() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(run.snapshot().sound.moving.size(), 1)
	assert_eq(run.snapshot().sound.moving[0].voice_tag, -1)
	run._tick_guard = RejectFinal.new()
	var command := TickCommand.new()
	var failed: TickResult = run.step(command)
	assert_eq(failed.error, "pickup sound rejected")
	assert_eq(run.snapshot().rng_state, 1)
	assert_eq(run.snapshot().sound.moving[0].voice_tag, -1)
	assert_eq(run.snapshot().entities.entities[0].matrix12[10], 0)
	assert_true(failed.events.is_empty())
	run._tick_guard = null
	var result: TickResult = run.step(command)
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.rng_consumers, ["sound:21:pitch", "entity:0:pickup_pitch_base", "entity:0:pickup_pitch_mod"])
	assert_true(result.final_snapshot.entities.entities[0].custom_state.moving_voice_active)
	assert_eq(result.final_snapshot.entities.entities[0].matrix12[10], 64)
	assert_eq(result.final_snapshot.sound.moving[0].voice_tag, 65536)
	assert_eq(run.reset(), "")
	assert_eq(run.snapshot().rng_state, 1)
	assert_eq(run.snapshot().sound.moving[0].voice_tag, -1)

func test_selective_recreation_retires_old_voice_and_preserves_shared_rng() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(run.step(TickCommand.new()).error, "")
	var state: GameplayState = run.snapshot()
	var random_before: int = state.rng_state
	run._candidate_entities = run._entities.copy()
	run._candidate_random = run._random.copy()
	var events: Array[TickEvent] = []
	assert_eq(run._reset_in_level(state, false, events), "")
	assert_eq(run._candidate_random.state, random_before)
	assert_not_null(state.sound.voices[0].sample)
	assert_true(state.sound.voices[0].killed)
	assert_false(state.sound.voices[0].playing)
	assert_eq(state.sound.moving.size(), 1)
	assert_eq(state.sound.moving[0].voice_tag, -1)
	assert_eq(state.sound.moving[0].generation, 1)
	assert_not_null(run.snapshot().sound.voices[0].sample)
	assert_eq(run.snapshot().sound.moving[0].generation, 0)

func test_script_requests_publish_at_their_source_position_once() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	var candidate: GameplayState = run.snapshot()
	var runtime := EntityScriptRuntime.new()
	runtime.state = candidate
	runtime.entity_index = 0
	var update := EntityUpdateResult.new()
	update.runtime = runtime
	update.random = SourceRandom.new()
	update.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0])
	var request: TickEvent = TickEvent.make(TickEvent.Kind.SOUND)
	request.sound_id = 21
	update.add_request(request)
	runtime.events.append(TickEvent.make(TickEvent.Kind.DEATH_ANIMATION))
	update.add_request(TickEvent.make(TickEvent.Kind.SPRITE))
	assert_eq(update.runtime_error, "")
	assert_eq(runtime.events.size(), 3)
	assert_eq(runtime.events[0].kind, TickEvent.Kind.SOUND)
	assert_eq(runtime.events[1].kind, TickEvent.Kind.DEATH_ANIMATION)
	assert_eq(runtime.events[2].kind, TickEvent.Kind.SPRITE)
	assert_true(update.effects[0].applied)
	assert_true(update.effects[1].applied)
	assert_eq(candidate.requests.sound_requests, 1)
	assert_eq(run.snapshot().requests.sound_requests, 0)
