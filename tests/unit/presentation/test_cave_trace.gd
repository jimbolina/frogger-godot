extends GutTest
## Schedule facts retain the shared cave light radii and applied entity colour scaling.

func test_light_radii_and_colour_scaling_are_in_detached_trace() -> void:
	var state := GameplayState.new()
	state.entity_environment = EntityEnvironmentState.new()
	state.entity_environment.light_min_squared = 0xF0000
	state.entity_environment.light_max_squared = 0x1F0000
	var facts: Dictionary = TerrainTrace.facts(state, true)
	var environment: Dictionary = facts.entity_environment
	var minimum: int = environment.light_min_squared
	var maximum: int = environment.light_max_squared
	assert_eq(minimum, 0xF0000)
	assert_eq(maximum, 0x1F0000)
	var entity := EntitySnapshot.new()
	entity.colour_scale = Vector3i.ZERO
	entity.colour_scaled = true
	var entity_facts: Dictionary = TerrainTrace.facts(entity, true)
	var scaled: bool = entity_facts.colour_scaled
	assert_true(scaled)
	assert_true(entity_facts.has("colour_scale"))
