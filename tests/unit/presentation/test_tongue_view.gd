extends GutTest
## The tongue ribbon shares the source projection correction applied to other gameplay materials.

func _active_state(tick: int) -> GameplayState:
	var state := GameplayState.new()
	state.tick_index = tick
	state.tongue.start(-1)
	state.tongue.advance()
	state.tongue.advance()
	return state

func _scale(view: TongueView) -> Vector2:
	var scale: Vector2 = view._material.get_shader_parameter("projection_scale")
	return scale

func test_projection_scale_applies_before_and_after_material_creation() -> void:
	var view := TongueView.new()
	add_child_autofree(view)
	var early := Vector2(1.0, 0.75)
	view.set_projection_scale(early)
	view.draw_state(_active_state(1))
	assert_true(view.visible)
	assert_not_null(view._material)
	assert_eq(_scale(view), early)
	var later := Vector2(1.25, 0.5)
	view.set_projection_scale(later)
	assert_eq(_scale(view), later)
	view.draw_state(_active_state(2))
	assert_eq(_scale(view), later)

func test_hidden_ribbon_retains_scale_for_its_first_material() -> void:
	var view := TongueView.new()
	add_child_autofree(view)
	var idle := GameplayState.new()
	view.draw_state(idle)
	assert_false(view.visible)
	assert_null(view._material)
	view.set_projection_scale(Vector2(1.0, 0.8))
	view.draw_state(_active_state(3))
	assert_eq(_scale(view), Vector2(1.0, 0.8))
