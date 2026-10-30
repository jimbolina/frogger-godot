extends GutTest
## The water view steps a shared frame count at 30 Hz, interpolates heights between ticks and
## owns the options camera only when asked.

const StackLayoutTest := preload("res://tests/unit/game/frontend/test_stack_layout.gd")


func _heights(frame: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for value: int in MenuWater.heights(frame):
		result.append(value)
	return result


func test_ticks_advance_and_interpolate_heights() -> void:
	var animation: MenuWater = MenuWater.create(10)
	var view: MenuWaterView = MenuWaterView.create(animation, null, null)
	autofree(view)
	assert_eq(view.meshes.water_positions, MenuWaterMesh.positions(MenuWater.water_vertices(), _heights(10)))
	view.tick()
	assert_eq(animation.frame_count, 11)
	assert_eq(view.meshes.water_positions, MenuWaterMesh.positions(MenuWater.water_vertices(), _heights(10)), "drawn at the previous tick")
	view.render(0.5)
	var halfway := PackedFloat32Array()
	var before: PackedFloat32Array = _heights(10)
	var after: PackedFloat32Array = _heights(11)
	for index: int in before.size():
		halfway.append(lerpf(before[index], after[index], 0.5))
	assert_eq(view.meshes.water_positions, MenuWaterMesh.positions(MenuWater.water_vertices(), halfway))
	view.render(1.0)
	assert_eq(view.meshes.water_positions, MenuWaterMesh.positions(MenuWater.water_vertices(), after))


func test_process_steps_at_thirty_hertz() -> void:
	var animation: MenuWater = MenuWater.create()
	var view: MenuWaterView = MenuWaterView.create(animation, null, null)
	autofree(view)
	view._process(MenuWaterView.PERIOD * 0.5)
	assert_eq(animation.frame_count, 0)
	view._process(MenuWaterView.PERIOD * 0.6)
	assert_eq(animation.frame_count, 1)
	view._process(MenuWaterView.PERIOD * 5.0)
	assert_eq(animation.frame_count, 2, "a long stall draws one tick and drops the rest")


func test_shared_animation_continues_across_views() -> void:
	var animation: MenuWater = MenuWater.create()
	var first: MenuWaterView = MenuWaterView.create(animation, null, null)
	autofree(first)
	first.tick()
	first.tick()
	var second: MenuWaterView = MenuWaterView.create(animation, null, null)
	autofree(second)
	assert_eq(second.meshes.water_positions, MenuWaterMesh.positions(MenuWater.water_vertices(), _heights(2)))


func test_main_menu_view_has_the_options_camera() -> void:
	var view: MenuWaterView = MenuWaterView.create_with_camera(MenuWater.create(), null, null)
	autofree(view)
	assert_not_null(view.camera)
	assert_almost_eq(view.camera.fov, GameplayProjection.vertical_fov_degrees(MenuWaterView.DISPLAY_SIZE), 0.00001)
	assert_gt(view.camera.far, MenuWaterMesh.RIVERBED_DEPTH)
	var forward: Vector3 = -view.camera.transform.basis.z.normalized()
	var axis: Vector3i = MenuWaterView.MAIN_TARGET - MenuWaterView.MAIN_SOURCE
	assert_almost_eq(forward, GameSpace.normal(axis.x, axis.y, axis.z).normalized(), Vector3.ONE * 0.001)
	assert_almost_eq(view.camera.transform.origin, GameSpace.position(0, -2500, -1280), Vector3.ONE * 0.0001)
	assert_gt(view.camera.transform.origin.y, 0.0, "above the water")
	var plain: MenuWaterView = MenuWaterView.create(MenuWater.create(), null, null)
	autofree(plain)
	assert_null(plain.camera)


func test_level_stack_hosts_the_water_in_its_world() -> void:
	var stack: LevelStack = StackLayoutTest.retail_stack()
	var animation: MenuWater = MenuWater.create()
	var view: LevelStackView = LevelStackView.create(FrontEndAssets.new(), stack, LevelProgress.create(stack), -1, true,
		Color.BLACK, animation)
	autofree(view)
	assert_not_null(view.water)
	assert_same(view.water.water, animation)
	assert_null(view.water.camera, "drawn through the stack camera")
	assert_same(view.water.get_parent(), view.camera.get_parent())
	assert_lt(MenuWaterMesh.RIVERBED_DEPTH, view.camera.far)
	var plain: LevelStackView = LevelStackView.create(FrontEndAssets.new(), stack, LevelProgress.create(stack), -1, true)
	autofree(plain)
	assert_null(plain.water)
