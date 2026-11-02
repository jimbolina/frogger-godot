extends GutTest
## The main menu's three sprite rows wrap their focus, slide with the fly counters, ask for the
## hop and croak sounds and report a fire only while the host allows it.

var _events: Array[int] = []
var _sounds: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_events.clear()
	_sounds = PackedStringArray()


func _view() -> MainMenuView:
	var view: MainMenuView = MainMenuView.create(FrontEndAssets.new(), null)
	view.menu_event.connect(_events.append)
	view.sound_requested.connect(_on_sound)
	add_child_autofree(view)
	return view


func _on_sound(sound_name: String) -> void:
	_sounds.append(sound_name)


func test_the_rows_sit_16_apart_from_the_rest_row_and_build_without_textures() -> void:
	var view: MainMenuView = _view()
	assert_eq(view.sprites.size(), 3)
	for index: int in 3:
		assert_null(view.sprites[index].texture_normal)
		assert_eq(view.sprites[index].position, Vector2(StackLayout.DISPLAY_WIDTH >> 1, MainMenuView.MENU_ROW_Y + index * 16))
	assert_eq(view.cloud.position.y, float(MainMenuView.MENU_ROW_Y - MainMenuView.CLOUD_BORDER))
	assert_eq(view.cloud.size.x, MainMenuView.CLOUD_BORDER * 2.0)


func test_the_slide_moves_the_sprites_and_the_cloud_down() -> void:
	var view: MainMenuView = _view()
	view.set_slide(80)
	assert_eq(view.slide(), 80)
	assert_eq(view.sprites[0].position.y, float(MainMenuView.MENU_ROW_Y + 80))
	assert_eq(view.sprites[2].position.y, float(MainMenuView.MENU_ROW_Y + 32 + 80))
	assert_eq(view.cloud.position.y, float(MainMenuView.MENU_ROW_Y - MainMenuView.CLOUD_BORDER + 80))
	view.set_slide(0)
	assert_eq(view.sprites[1].position.y, float(MainMenuView.MENU_ROW_Y + 16))


func test_focus_wraps_both_ways() -> void:
	var view: MainMenuView = _view()
	var count: int = view.sprites.size()
	for index: int in count:
		var sprite: TextureButton = view.sprites[index]
		assert_eq(sprite.get_node(sprite.focus_neighbor_top), view.sprites[(index + count - 1) % count])
		assert_eq(sprite.get_node(sprite.focus_neighbor_bottom), view.sprites[(index + 1) % count])


func test_the_first_focus_is_quiet_and_later_moves_hop() -> void:
	var view: MainMenuView = _view()
	view.grab_first_focus()
	await wait_process_frames(1)
	assert_true(view.sprites[0].has_focus())
	assert_eq(view.option_number, 0)
	assert_eq(_sounds, PackedStringArray(), "the first focus does not hop")
	view.sprites[2].grab_focus()
	assert_eq(view.option_number, 2)
	assert_eq(_sounds, PackedStringArray([MainMenuView.HOP_SOUND]))
	assert_eq(view.sprites[2].modulate, MainMenuView.FOCUS_COLOUR)
	assert_eq(view.sprites[0].modulate, Color.WHITE)


func test_a_kept_row_takes_the_first_focus_without_a_hop() -> void:
	var view: MainMenuView = _view()
	view.option_number = 1
	view.grab_first_focus()
	await wait_process_frames(1)
	assert_true(view.sprites[1].has_focus())
	view.focus_row(2)
	assert_true(view.sprites[2].has_focus())
	assert_eq(view.option_number, 2)
	assert_eq(_sounds, PackedStringArray(), "a host-chosen row does not hop")


func test_fire_croaks_and_reports_the_row() -> void:
	var view: MainMenuView = _view()
	view.focus_row(1)
	view.sprites[1].pressed.emit()
	assert_eq(_events, [MainMenuView.Kind.OPTIONS] as Array[int])
	assert_eq(_sounds, PackedStringArray([MainMenuView.CROAK_SOUND]))
	view.sprites[2].pressed.emit()
	assert_eq(_events, [MainMenuView.Kind.OPTIONS, MainMenuView.Kind.EXIT] as Array[int])
	assert_eq(view.option_number, 2)


func test_a_closed_fire_is_ignored_silently() -> void:
	var view: MainMenuView = _view()
	view.fire_allowed = false
	view.sprites[0].pressed.emit()
	assert_eq(_events.size(), 0)
	assert_eq(_sounds, PackedStringArray())
	view.fire_allowed = true
	view.sprites[0].pressed.emit()
	assert_eq(_events, [MainMenuView.Kind.START] as Array[int])
