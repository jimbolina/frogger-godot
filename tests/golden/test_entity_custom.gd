extends GutTest
## Independent frozen custom-entity state machines and source integer narrowing.

func test_crocodile_state_machine_matches_independent_facts() -> void:
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/entity_custom.json"))
	for fixture: Dictionary in facts.crocodiles:
		var definition := EntityDefinition.new()
		definition.entity_index = 55
		definition.behavior = EntityBehaviorCatalog.resolve("ORG_CROC_HEAD")
		definition.behavior.execution = EntityBehavior.Execution.CONTACT
		var entity := EntitySnapshot.new()
		entity.custom_state = EntityCustomState.new()
		entity.custom_state.timer = 0
		entity.custom_state.model_hidden = true
		entity.entity_flags = 9
		entity.animation = EntityAnimationState.create([30])
		var environment := EntityEnvironmentState.new()
		environment.collected = fixture.blocked
		for index: int in 5:
			environment.checkpoint_positions.append(Vector3i(1000 + index * 256, -32760, 32760))
		var random: SourceRandom = SourceRandom.create(1)
		var frog := GameplayState.new()
		for row: Dictionary in fixture.rows:
			frog.frog.mode = FrogMode.HIT_CHECKPOINT if row.tick == fixture.checkpoint_tick else FrogMode.STATIONARY
			var hit: bool = row.tick == fixture.hit_tick
			var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, environment, random, Vector3i.ZERO, hit, false, null, null, frog)
			assert_eq(result.error, "")
			if not result.error.is_empty():
				return
			entity = result.entity
			environment = result.environment
			random = result.random
			var observed: Dictionary = {"tick": row.tick, "mode": entity.custom_state.mode, "timer": entity.custom_state.timer, "checkpoint": entity.custom_state.checkpoint_index, "delay": entity.custom_state.delay, "covered": environment.covered, "disabled": environment.collision_disabled, "flags": entity.entity_flags, "hidden": entity.custom_state.model_hidden, "matrix": Array(entity.matrix12), "rng": random.state, "draws": random.draw_count, "death": result.death_animation, "moving": not entity.custom_state.moving_sound.is_empty()}
			for key: String in observed:
				if key == "matrix":
					var expected_values: Array = row.matrix
					var expected_matrix := PackedInt32Array(expected_values)
					assert_eq(entity.matrix12, expected_matrix, "tick %d matrix" % row.tick)
				elif observed[key] is bool:
					var expected_flag: bool = row[key]
					var actual_flag: bool = observed[key]
					assert_eq(actual_flag, expected_flag, "tick %d %s" % [row.tick, key])
				else:
					var expected_number: int = row[key]
					var actual_number: int = observed[key]
					assert_eq(actual_number, expected_number, "tick %d %s" % [row.tick, key])

func _environment() -> EntityEnvironmentState:
	var result := EntityEnvironmentState.new()
	result.checkpoint_positions.resize(5)
	return result

func _assert_custom_row(observed: Dictionary, expected: Dictionary, label: String) -> void:
	for key: String in observed:
		if observed[key] is Array:
			var actual_values: Array = observed[key]
			var expected_values: Array = expected[key]
			assert_eq(PackedInt32Array(actual_values), PackedInt32Array(expected_values), "%s %s" % [label, key])
		elif observed[key] is bool:
			var actual_flag: bool = observed[key]
			var expected_flag: bool = expected[key]
			assert_eq(actual_flag, expected_flag, "%s %s" % [label, key])
		else:
			var actual_number: int = observed[key]
			var expected_number: int = expected[key]
			assert_eq(actual_number, expected_number, "%s %s" % [label, key])

func test_gold_frog_pop_and_repeated_hit_match_independent_facts() -> void:
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/entity_custom.json"))
	for fixture: Dictionary in facts.gold_frogs:
		var definition := EntityDefinition.new()
		definition.behavior = EntityBehaviorCatalog.resolve("GEN_GOLD_FROG")
		definition.behavior.execution = EntityBehavior.Execution.CONTACT
		var entity := EntitySnapshot.new()
		entity.custom_state = EntityCustomState.new()
		entity.custom_state.mode = EntityGoldFrog.Mode.WAITING
		entity.custom_state.model_hidden = fixture.collected
		if fixture.collected:
			definition.entity_index = 0
			definition.form_flags = 16
			definition.action_lengths = PackedInt32Array([4])
			var definitions: Array[EntityDefinition] = [definition]
			var run: EntityRun = EntityRun.create(definitions)
			assert_eq(run.error, "")
			if not run.error.is_empty():
				return
			assert_eq(run.reset_in_level(false, _environment(), true), "")
			entity = run.entity_snapshot(0)
			assert_null(entity.animation)
		for row: Dictionary in fixture.rows:
			entity.requests.clear()
			var hit: bool = row.hit
			var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, _environment(), SourceRandom.create(17), Vector3i.ZERO, hit, false)
			assert_eq(result.error, "")
			if not result.error.is_empty():
				return
			entity = result.entity
			entity.pop_remaining = maxi(0, entity.pop_remaining - 1)
			_assert_custom_row({"mode": entity.custom_state.mode, "remaining": entity.pop_remaining, "allocated": entity.pop_allocated, "hidden": entity.custom_state.model_hidden, "request": not entity.requests.is_empty()}, row, "gold tick %d" % row.tick)
			assert_eq(result.random.state, 17)
			assert_eq(result.random.draw_count, 0)

func test_log_snake_narrowing_visibility_and_recreation_match_independent_facts() -> void:
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/entity_custom.json"))
	for fixture: Dictionary in facts.snakes:
		var definition := EntityDefinition.new()
		definition.behavior = EntityBehaviorCatalog.resolve("ORG_LOG_SNAKE")
		definition.behavior.execution = EntityBehavior.Execution.CONTACT
		var radius: int = fixture.snake_radius
		definition.radius_squared = radius * radius
		definition.movement_speed = fixture.speed
		var form := FormContactDefinition.new()
		radius = fixture.log_radius
		form.radius_squared = radius * radius
		form.height = fixture.height
		var parent := EntitySnapshot.new()
		parent.entity_index = 7
		parent.path = PathSnapshot.new()
		parent.path.position = Vector3i(100, 200, 300)
		parent.matrix12 = PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 100, 200, 300])
		var entity := EntitySnapshot.new()
		entity.custom_state = EntityCustomState.new()
		for row: Dictionary in fixture.rows:
			if row.recreate:
				entity = EntitySnapshot.new()
				entity.custom_state = EntityCustomState.new()
			entity.requests.clear()
			parent.live = row.live
			var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, _environment(), SourceRandom.create(17), Vector3i.ZERO, false, parent.live, parent, form)
			assert_eq(result.error, "")
			if not result.error.is_empty():
				return
			entity = result.entity
			_assert_custom_row({"direction": entity.custom_state.direction, "range": entity.custom_state.count, "offset": entity.custom_state.target.z, "height": entity.custom_state.target.y, "hidden": entity.custom_state.model_hidden, "request": not entity.requests.is_empty(), "matrix": Array(entity.matrix12)}, row, "snake tick %d" % row.tick)
			assert_eq(result.random.state, 17)
			assert_eq(result.random.draw_count, 0)

func test_beaver_path_order_clocks_and_bite_match_independent_facts() -> void:
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/entity_custom.json"))
	for fixture: Dictionary in facts.beavers:
		var definition := EntityDefinition.new()
		definition.entity_index = 11
		definition.behavior = EntityBehaviorCatalog.resolve("ORG_BEAVER")
		definition.behavior.execution = EntityBehavior.Execution.CONTACT
		definition.path_definition = PathDefinition.new()
		var order: Array = fixture.get("order", [5, 9])
		definition.path_definition.entity_indices = PackedInt32Array(order)
		definition.authored_delay = 1
		var entity := EntitySnapshot.new()
		entity.custom_state = EntityCustomState.new()
		entity.custom_state.mode = fixture.mode
		entity.custom_state.delay = fixture.get("delay", 0)
		entity.custom_state.count = fixture.get("count", 0)
		entity.custom_state.parent_entity_index = 5
		entity.animation = EntityAnimationState.create([20, 20])
		entity.path = PathSnapshot.new()
		entity.path.tangent = Vector3i(0, 0, 4096)
		var neighbors: Array[EntitySnapshot] = []
		var definitions: Array[EntityDefinition] = []
		for slot: int in 2:
			var neighbor := EntitySnapshot.new()
			neighbor.entity_index = 5 if slot == 0 else 9
			neighbor.live = fixture.get("live", true)
			neighbor.path = PathSnapshot.new()
			var position: Array = fixture.positions[slot]
			var x: int = position[0]
			var y: int = position[1]
			var z: int = position[2]
			neighbor.path.position = Vector3i(x, y, z)
			neighbors.append(neighbor)
			definitions.append(EntityDefinition.new())
		var frog := GameplayState.new()
		frog.attachment.current_entity_index = 5
		frog.frog.matrix12[9] = fixture.get("frog", 1000)
		for row: Dictionary in fixture.rows:
			entity.requests.clear()
			var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, _environment(), SourceRandom.create(17), Vector3i.ZERO, false, false, null, null, frog, neighbors, definitions)
			assert_eq(result.error, "")
			if not result.error.is_empty():
				return
			entity = result.entity
			_assert_custom_row({"mode": entity.custom_state.mode, "delay": entity.custom_state.delay, "timer": entity.custom_state.timer, "count": entity.custom_state.count, "parent": entity.custom_state.parent_entity_index, "hidden": entity.custom_state.model_hidden, "moving": not entity.custom_state.moving_sound.is_empty(), "action": entity.animation.action, "one_shot": entity.animation.one_shot, "colour": [entity.colour_scale.x, entity.colour_scale.y, entity.colour_scale.z], "ambient": [entity.ambient.x, entity.ambient.y, entity.ambient.z], "faded": bool(entity.live_flags & EntityLiveFlags.NO_SCREEN_FADE), "y": entity.matrix12[10], "reset": result.path_reset_requested, "active": result.path_active_request, "death": result.death_animation, "request": not entity.requests.is_empty()}, row, "%s tick %d" % [fixture.name, row.tick])
			assert_eq(result.random.state, 17)
			assert_eq(result.random.draw_count, 0)
