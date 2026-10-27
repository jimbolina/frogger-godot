extends GutTest
## Schedule facts retain all Volcano continuation and presentation state.

func test_switch_state_and_animation_step_are_in_detached_trace() -> void:
	var entity := EntitySnapshot.new()
	entity.custom_state = EntityCustomState.new()
	entity.custom_state.initialized = true
	entity.custom_state.no_frog_contact = true
	entity.custom_state.texture_animation_paused = true
	entity.custom_state.texture_animation_cel = 1
	entity.animation = EntityAnimationState.new()
	entity.animation.stepping = false
	var facts: Dictionary = TerrainTrace.facts(entity, true)
	var background: Dictionary = facts.background
	var animation: Dictionary = facts.animation
	var initialized: bool = background.initialized
	var no_contact: bool = background.no_frog_contact
	var paused: bool = background.texture_animation_paused
	var cel: int = background.texture_animation_cel
	var stepping: bool = animation.stepping
	assert_true(initialized)
	assert_true(no_contact)
	assert_true(paused)
	assert_eq(cel, 1)
	assert_false(stepping)
