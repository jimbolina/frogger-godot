extends GutTest
## FrogLordOverlay chooses the overlay a level opens: the pointer's under
## --froglord, the pointer's over the same base and folder with FrogLord on in
## the setup, and the base root for attract demos, with FrogLord off, or before
## the game has imported an overlay over this base.

const FOLDER: String = "/FrogLord/save"
const BASE: String = "user://assets/0123456789abcdef"
const INDEX: String = "user://froglord/over-x/fedcba9876543210"


func _launcher(enabled: bool, folder: String = FOLDER) -> LauncherSettings:
	var settings := LauncherSettings.new()
	settings.froglord_enabled = enabled
	settings.froglord_dir = folder
	return settings


func _pointer(fallback: String = BASE, folder: String = FOLDER) -> FrogLordPointer:
	var pointer := FrogLordPointer.new()
	pointer.index_root = INDEX
	pointer.data_dir = folder
	pointer.fallback_root = fallback
	var path: String = "user://froglord_overlay_test.cfg"
	assert_eq(pointer.write(path), OK)
	var read: FrogLordPointer = FrogLordPointer.read(path)
	DirAccess.remove_absolute(path)
	return read


func test_froglord_off_plays_the_base_root() -> void:
	var choice: FrogLordOverlay = FrogLordOverlay.choose(false, _launcher(false), false, _pointer(), BASE)
	assert_false(choice.follows)
	assert_eq(choice.index_root, "")
	assert_eq(choice.note, "")
	assert_false(FrogLordOverlay.choose(false, null, false, _pointer(), BASE).follows)
	assert_false(FrogLordOverlay.choose(false, _launcher(true, ""), false, _pointer(), BASE).follows, "no folder: off")


func test_froglord_on_opens_the_overlay_of_the_same_folder_over_the_same_base() -> void:
	var choice: FrogLordOverlay = FrogLordOverlay.choose(false, _launcher(true), false, _pointer(), BASE)
	assert_true(choice.follows)
	assert_eq(choice.index_root, INDEX)
	assert_eq(choice.note, "")


func test_froglord_on_waits_on_the_base_root_for_an_overlay_it_can_use() -> void:
	for pointer: FrogLordPointer in [null, FrogLordPointer.new(), _pointer("res://assets"), _pointer(BASE, "/elsewhere")]:
		var choice: FrogLordOverlay = FrogLordOverlay.choose(false, _launcher(true), false, pointer, BASE)
		assert_true(choice.follows, "the level still reloads when the watch imports one")
		assert_eq(choice.index_root, "")
		assert_string_contains(choice.note, "No FrogLord overlay of %s over %s" % [FOLDER, BASE])


func test_attract_demos_keep_the_base_root() -> void:
	var choice: FrogLordOverlay = FrogLordOverlay.choose(true, _launcher(true), true, _pointer(), BASE)
	assert_false(choice.follows)
	assert_eq(choice.index_root, "")


func test_the_froglord_flag_follows_any_pointer() -> void:
	var choice: FrogLordOverlay = FrogLordOverlay.choose(true, null, false, _pointer("res://assets"), BASE)
	assert_true(choice.follows)
	assert_eq(choice.index_root, INDEX)
	var none: FrogLordOverlay = FrogLordOverlay.choose(true, _launcher(false), false, FrogLordPointer.new(), BASE)
	assert_true(none.follows)
	assert_eq(none.index_root, "")
	assert_string_contains(none.note, "No FrogLord overlay pointer")
