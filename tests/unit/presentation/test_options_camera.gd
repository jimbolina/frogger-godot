extends GutTest
## The options camera sweeps between presets exactly as the water golden's sweeps record.

const WATER_GOLDEN: String = "res://tests/golden/synthetic/frontend_water.json"


func _cameras() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WATER_GOLDEN))
	assert_true(parsed is Dictionary, "water golden parses")
	var document: Dictionary = parsed
	var cameras: Dictionary = document["cameras"]
	return cameras["options"]


func _vector(value: Variant) -> Vector3i:
	var values: Array = value
	var x: float = values[0]
	var y: float = values[1]
	var z: float = values[2]
	return Vector3i(int(x), int(y), int(z))


func _number(row: Dictionary, key: String) -> int:
	var value: float = row[key]
	return int(value)


func _check_sweep(start: int, goal: int, value: Variant) -> void:
	var rows: Array = value
	var rig := OptionsCamera.new()
	rig.source = OptionsCamera.preset_source(start)
	rig.target = OptionsCamera.preset_target(start)
	rig.aim(goal, OptionsMenu.CAMERA_MOVE_TIME)
	for row: Dictionary in rows:
		rig.tick()
		var tick: int = _number(row, "tick")
		assert_eq(rig.timer, _number(row, "timer"), "tick %d timer" % tick)
		assert_eq(rig.source, _vector(row["source"]), "tick %d source" % tick)
		assert_eq(rig.target, _vector(row["target"]), "tick %d target" % tick)


func test_presets_match_the_water_golden() -> void:
	var presets: Dictionary = _cameras()["presets"]
	var kinds: Dictionary[String, int] = {"MAIN": OptionsMenu.Camera.MAIN, "OPTIONS": OptionsMenu.Camera.OPTIONS}
	for preset_name: String in kinds:
		var preset: Dictionary = presets[preset_name]
		assert_eq(OptionsCamera.preset_source(kinds[preset_name]), _vector(preset["source"]), preset_name)
		assert_eq(OptionsCamera.preset_target(kinds[preset_name]), _vector(preset["target"]), preset_name)


func test_sweeps_match_the_water_golden() -> void:
	var cameras: Dictionary = _cameras()
	_check_sweep(OptionsMenu.Camera.MAIN, OptionsMenu.Camera.OPTIONS, cameras["sweep_main_to_options"])
	_check_sweep(OptionsMenu.Camera.OPTIONS, OptionsMenu.Camera.MAIN, cameras["sweep_options_to_main"])


func test_menu_driven_moves_follow_the_menu_timer_and_stop_at_zero() -> void:
	var rig := OptionsCamera.new()
	var menu := OptionsMenu.create()
	for _tick: int in OptionsMenu.FLY_ON_TIME:
		menu.step(OptionsMenu.Buttons.new(), 0)
		rig.move(menu.camera, menu.camera_timer)
	assert_eq(rig.source, OptionsCamera.OPTIONS_SOURCE)
	assert_eq(rig.target, OptionsCamera.OPTIONS_TARGET)
	rig.move(OptionsMenu.Camera.CONTROLS, 0)
	assert_eq(rig.source, OptionsCamera.OPTIONS_SOURCE, "a zero timer does not move")
