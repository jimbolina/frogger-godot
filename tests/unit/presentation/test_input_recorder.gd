extends GutTest
## Owner playthrough recordings use the sparse keyboard fixture format the capture launcher replays.

func _command(tick: int, held: int) -> TickCommand:
	var command := TickCommand.new()
	command.tick_index = tick
	command.held_mask = held
	return command

func test_command_line_flag_selects_recording_and_optional_path() -> void:
	assert_null(InputRecorder.from_arguments(PackedStringArray(["--level=CAV3"])))
	var default_recorder: InputRecorder = InputRecorder.from_arguments(PackedStringArray(["--record-inputs"]))
	assert_not_null(default_recorder)
	assert_eq(default_recorder.output_path, "")
	var explicit: InputRecorder = InputRecorder.from_arguments(PackedStringArray(["--record-inputs=user://custom.json"]))
	assert_eq(explicit.output_path, "user://custom.json")

func test_recording_keeps_last_held_mask_per_tick_and_omits_releases() -> void:
	var recorder := InputRecorder.new()
	recorder.reset("CAV3")
	recorder.record(_command(5, 0))
	recorder.record(_command(7, TickCommand.NORTH))
	recorder.record(_command(7, TickCommand.EAST))
	recorder.record(_command(9, TickCommand.SUPER_HOP | 256))
	recorder.record(_command(9, 0))
	recorder.record(_command(3, TickCommand.WEST))
	assert_eq(recorder.inputs(), [[3, TickCommand.WEST], [7, TickCommand.EAST]])
	var document: Dictionary = recorder.document(41)
	var ticks: int = document.ticks
	var goal: String = document.goal
	var level: String = document.level
	assert_eq(ticks, 42)
	assert_eq(goal, "complete")
	assert_eq(level, "CAV3")
	recorder.reset("CAV1")
	assert_eq(recorder.inputs(), [])
	assert_eq(recorder.saved_path, "")

func test_save_writes_replayable_fixture_json() -> void:
	var recorder := InputRecorder.new()
	recorder.output_path = "user://test_input_recorder/cav3_keyboard_playthrough.json"
	recorder.reset("CAV3")
	recorder.record(_command(122, TickCommand.NORTH))
	recorder.record(_command(140, TickCommand.SUPER_HOP))
	assert_eq(recorder.save(2400), "")
	assert_true(recorder.saved_path.ends_with("cav3_keyboard_playthrough.json"))
	assert_true(recorder.saved_path.is_absolute_path())
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(recorder.output_path))
	assert_true(parsed is Dictionary)
	var route: Dictionary = parsed
	var inputs: Array = route.inputs
	assert_eq(inputs.size(), 2)
	var first: Array = inputs[0]
	var first_tick: float = first[0]
	var first_mask: float = first[1]
	assert_eq(int(first_tick), 122)
	assert_eq(int(first_mask), TickCommand.NORTH)
	var ticks: float = route.ticks
	assert_eq(int(ticks), 2401)
	DirAccess.remove_absolute(recorder.saved_path)
