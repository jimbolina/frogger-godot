extends GutTest
## The game-over shrink narrows the game viewport: the camera's field of view widens so the scene
## scales by width / 640 about the centre, a zero width draws no world, and the empty rect, a
## fresh run or a size change restore or reapply it.

var _view: GameplayWorldView


func before_each() -> void:
	_view = GameplayWorldView.new()
	add_child_autofree(_view)
	_view.build_world()


func _full_fov() -> float:
	return GameplayProjection.vertical_fov_degrees(Vector2i(_view.get_viewport().get_visible_rect().size))


func _scaled_fov(width: int) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(_full_fov()) * 0.5) * 640.0 / width))


func test_a_narrower_viewport_widens_the_field_of_view() -> void:
	_view.set_view_rect(Rect2i(165, 124, 310, 232))
	assert_almost_eq(_view._camera.fov, _scaled_fov(310), 0.0001)
	assert_ne(_view._camera.cull_mask, 0)
	_view.set_view_rect(Rect2i(0, 0, 640, 480))
	assert_almost_eq(_view._camera.fov, _full_fov(), 0.0001)
	_view.set_view_rect(Rect2i())
	assert_almost_eq(_view._camera.fov, _full_fov(), 0.0001, "the empty rect restores the display")


func test_a_zero_width_draws_no_world_and_the_empty_rect_brings_it_back() -> void:
	var mask: int = _view._camera.cull_mask
	_view.set_view_rect(Rect2i(320, 240, 0, 0))
	assert_eq(_view._camera.cull_mask, 0)
	assert_lte(_view._camera.fov, 179.0)
	_view.set_view_rect(Rect2i())
	assert_eq(_view._camera.cull_mask, mask)


func test_the_field_of_view_stays_within_the_camera_limit() -> void:
	assert_eq(GameplayWorldView.view_fov_degrees(50.0, 640), 50.0)
	assert_eq(GameplayWorldView.view_fov_degrees(50.0, 0), 50.0)
	assert_eq(GameplayWorldView.view_fov_degrees(50.0, 1), 179.0)
	assert_almost_eq(GameplayWorldView.view_fov_degrees(50.0, 320), rad_to_deg(2.0 * atan(tan(deg_to_rad(25.0)) * 2.0)), 0.0001)


func test_a_size_change_reapplies_the_rect() -> void:
	_view.set_view_rect(Rect2i(100, 75, 440, 330))
	_view._camera.fov = 45.0
	_view._projection_size = Vector2i.ZERO
	_view._update_projection()
	assert_almost_eq(_view._camera.fov, _scaled_fov(440), 0.0001)


func test_a_fresh_run_restores_the_display() -> void:
	_view.set_view_rect(Rect2i(100, 75, 440, 330))
	var state := GameplayState.new()
	state.entities = EntityRunSnapshot.new()
	_view.accept_state(state)
	assert_eq(_view.view_rect(), Rect2i())
	assert_almost_eq(_view._camera.fov, _full_fov(), 0.0001)
