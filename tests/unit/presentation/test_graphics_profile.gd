extends GutTest
## GraphicsProfile keeps one live record and announces each replacement once.

var _changes: int = 0


func after_each() -> void:
	var live: GraphicsSettings = GraphicsProfile.current()
	if live.changed.is_connected(_count):
		live.changed.disconnect(_count)
	GraphicsProfile.reset()


func _count() -> void:
	_changes += 1


func test_current_is_the_same_instance_every_call() -> void:
	assert_same(GraphicsProfile.current(), GraphicsProfile.current())


func test_replace_copies_values_into_the_same_record() -> void:
	var live: GraphicsSettings = GraphicsProfile.current()
	var values := GraphicsSettings.new()
	values.bloom = false
	values.max_fps = 90
	GraphicsProfile.replace(values)
	assert_same(GraphicsProfile.current(), live)
	assert_false(live.bloom)
	assert_eq(live.max_fps, 90)
	assert_ne(live, values)


func test_replace_emits_changed_once() -> void:
	_changes = 0
	GraphicsProfile.current().changed.connect(_count)
	var values := GraphicsSettings.new()
	values.render_scale = 0.5
	values.taa = true
	values.tonemapper = GraphicsSettings.Tonemapper.FILMIC
	GraphicsProfile.replace(values)
	assert_eq(_changes, 1)


func test_mutating_the_source_after_replace_does_not_leak() -> void:
	var values := GraphicsSettings.new()
	values.window_size = Vector2i(1024, 768)
	GraphicsProfile.replace(values)
	values.window_size = Vector2i(640, 480)
	values.ssao = true
	assert_eq(GraphicsProfile.current().window_size, Vector2i(1024, 768))
	assert_false(GraphicsProfile.current().ssao)


func test_reset_restores_defaults_and_emits_once() -> void:
	var values := GraphicsSettings.new()
	values.real_shadows = false
	GraphicsProfile.replace(values)
	_changes = 0
	GraphicsProfile.current().changed.connect(_count)
	GraphicsProfile.reset()
	assert_eq(_changes, 1)
	var defaults := GraphicsSettings.new()
	for field: String in GraphicsSettings.field_names():
		var live: Variant = GraphicsProfile.current().get(field)
		var expected: Variant = defaults.get(field)
		assert_eq(var_to_str(live), var_to_str(expected), field)
