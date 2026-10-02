extends GutTest
## Named source catalog and every script/pose field match independent Python/C facts.

func _catalog() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/frog_animation_catalog.json"))
	if parsed is Dictionary:
		return parsed
	return {}

func _lengths() -> PackedInt32Array:
	var lengths: Array = _catalog()["action_lengths"]
	return PackedInt32Array(lengths)

func _request_fixture(controller: FrogAnimationController, scenario: int, tick: int) -> void:
	match scenario:
		0:
			if tick in [0, 7]:
				controller.request(FrogAnimationCatalog.HOP)
			if tick in [1, 8]:
				controller.request(FrogAnimationCatalog.PANT)
		1:
			if tick == 0:
				controller.request(FrogAnimationCatalog.FREEFALL)
			if tick in [2, 7]:
				controller.request(FrogAnimationCatalog.PANT)
			if tick == 6:
				controller.request(FrogAnimationCatalog.HOP)
		2:
			if tick == 0:
				controller.request(FrogAnimationCatalog.DROWN)
			if tick == 3:
				controller.request(FrogAnimationCatalog.HOP)
			if tick == 8:
				controller.initialise(FrogAnimationCatalog.PANT)
		4:
			if tick == 0:
				controller.request(FrogAnimationCatalog.SLIPLEFT)
			if tick == 2:
				controller.request(FrogAnimationCatalog.SLIPRIGHT)

func test_named_source_catalog_and_actions() -> void:
	var facts: Dictionary = _catalog()
	var entries: Array = facts["entries"]
	assert_eq(entries.size(), 35)
	assert_eq(FrogAnimationCatalog.ACTION_NAMES.size(), 34)
	for index: int in entries.size():
		var entry: Dictionary = entries[index]
		assert_eq(str(FrogAnimationCatalog.NAMES[index]), str(entry["name"]))
		var flags: float = entry["flags"]
		var words: Array = entry["words"]
		assert_eq(FrogAnimationCatalog.FLAGS[index], int(flags))
		assert_eq(FrogAnimationCatalog.program(index), PackedInt32Array(words))
	var actions: Array = facts["actions"]
	for index: int in actions.size():
		assert_eq(str(FrogAnimationCatalog.ACTION_NAMES[index]), str(actions[index]))

func test_every_script_and_pose_component_field() -> void:
	var text: String = FileAccess.get_file_as_string("res://tests/golden/synthetic/frog_animation_components.csv")
	var rows: PackedStringArray = text.split("\n", false)
	rows.remove_at(0)
	assert_eq(rows.size(), 320)
	var row_index: int = 0
	for scenario: int in 5:
		var context: FrogAnimationContext = FrogAnimationContext.create(SourceRandom.create(1), &"JUN" if scenario == 3 else &"SUB")
		var controller: FrogAnimationController = FrogAnimationController.create(_lengths(), context)
		assert_eq(controller.error, "")
		for tick: int in (64 if scenario == 3 else 24):
			_request_fixture(controller, scenario, tick)
			controller.update_scripts(30 if scenario == 3 else 0)
			for phase: String in ["scripts", "pose"]:
				if phase == "pose":
					controller.advance_pose()
				var row: PackedStringArray = rows[row_index].strip_edges().split(",")
				assert_eq(row.size(), 29)
				assert_eq(row[0], str(scenario))
				assert_eq(row[1], str(tick))
				assert_eq(row[2], phase)
				var actual: PackedInt64Array = controller.state.facts(context)
				for field: int in actual.size():
					assert_eq(str(actual[field]), row[field + 3], "scenario %d tick %d %s field %d" % [scenario, tick, phase, field])
				assert_eq(controller.error, "")
				row_index += 1
	assert_eq(row_index, 320)

func test_copied_metadata_snapshot_and_context_are_detached() -> void:
	var lengths: PackedInt32Array = _lengths()
	var context: FrogAnimationContext = FrogAnimationContext.create(SourceRandom.create(1))
	var controller: FrogAnimationController = FrogAnimationController.create(lengths, context)
	lengths[0] = 99
	assert_eq(controller.state.total_cels, 3)
	var cloned_context: FrogAnimationContext = context.copy(context.random.copy())
	var clone: FrogAnimationController = controller.copy(cloned_context)
	clone.request(FrogAnimationCatalog.HOP)
	clone.update_scripts(0)
	clone.advance_pose()
	assert_eq(controller.state.script_type, FrogAnimationCatalog.PANT)
	assert_eq(controller.state.action, 0)
	assert_eq(controller.state.cel, 0)
	assert_eq(clone.state.action, 16)
	assert_eq(clone.state.cel, 0)
	var snapshot: FrogAnimationState = clone.state.copy()
	snapshot.cel = 99
	assert_eq(clone.state.cel, 0)

func test_invalid_action_metadata_and_unknown_animation_are_refused() -> void:
	var context: FrogAnimationContext = FrogAnimationContext.create(SourceRandom.create(1))
	assert_false(FrogAnimationController.create(PackedInt32Array(), context).error.is_empty())
	var lengths: PackedInt32Array = _lengths()
	lengths[4] = 0
	assert_false(FrogAnimationController.create(lengths, context).error.is_empty())
	var controller: FrogAnimationController = FrogAnimationController.create(_lengths(), context)
	assert_false(controller.request(999))
	assert_eq(controller.state.script_type, FrogAnimationCatalog.PANT)
