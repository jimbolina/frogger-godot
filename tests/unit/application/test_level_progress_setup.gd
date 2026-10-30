extends GutTest
## Stack construction from a synthetic level-select table and the plain progress mapping.

const S: int = LevelProgress.SELECTABLE
const Z: int = LevelProgress.ZONE_ACCESSIBLE
const C: int = LevelProgress.COMPLETED

func _entry(level: int, world: int, position: int, theme: int, local: int, count: int) -> LevelSelectEntry:
	var entry := LevelSelectEntry.new()
	entry.level = level
	entry.world = world
	entry.stack_position = position
	entry.theme = theme
	entry.local_level = local
	entry.levels_in_world = count
	return entry

func _table() -> LevelSelectTable:
	var table := LevelSelectTable.new()
	table.arcade.append(_entry(24, 1, 0, 5, 0, 2))
	table.arcade.append(_entry(25, 1, 0, 5, 1, 2))
	table.arcade.append(_entry(0, 7, 1, 1, 0, 1))
	table.arcade.append(_entry(18, 8, 2, 4, 0, 1))
	table.race.append(_entry(29, 1, 0, 5, 0, 1))
	return table

func test_stack_keeps_table_rows_and_order() -> void:
	var stack: LevelStack = LevelProgressSetup.stack_from_table(_table())
	assert_eq(stack.arcade_count(), 4)
	assert_eq(stack.race_count(), 1)
	var row: LevelStack.Row = stack.arcade_row(1)
	assert_eq([row.level, row.world, row.stack_position, row.theme, row.local_level, row.levels_in_world], [25, 1, 0, 5, 1, 2])
	assert_eq(stack.arcade_row(3).level, 18)
	assert_eq(stack.race_row(0).level, 29)

func test_dictionary_holds_only_plain_saved_values() -> void:
	var stack: LevelStack = LevelProgressSetup.stack_from_table(_table())
	var progress: LevelProgress = LevelProgress.create(stack)
	progress.complete_level(24)
	progress.collect_gold_frog(5)
	var data: Dictionary = LevelProgressSetup.to_dictionary(progress)
	assert_eq(data, {"arcade_flags": [C | S | Z, Z, S | Z, 0], "gold_frogs": 1 << 5})
	assert_eq(typeof(data["arcade_flags"]), TYPE_ARRAY)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(data))
	assert_eq(parsed.size(), 2, "The mapping survives JSON")

func test_round_trip_restores_flags_and_gold_frogs() -> void:
	var stack: LevelStack = LevelProgressSetup.stack_from_table(_table())
	var progress: LevelProgress = LevelProgress.create(stack)
	progress.complete_level(24)
	progress.open_level(25)
	progress.collect_gold_frog(9)
	var diagnostics := PackedStringArray()
	var restored: LevelProgress = LevelProgressSetup.from_dictionary(stack, LevelProgressSetup.to_dictionary(progress), diagnostics)
	assert_eq(diagnostics, PackedStringArray())
	assert_eq(restored.arcade_flags, progress.arcade_flags)
	assert_eq(restored.gold_frogs, progress.gold_frogs)
	assert_eq(restored.gold_frogs_current, 0, "Current-game bits are not saved")

func test_json_numbers_load_as_integers() -> void:
	var stack: LevelStack = LevelProgressSetup.stack_from_table(_table())
	var data: Dictionary = JSON.parse_string('{"arcade_flags": [7, 6, 0, 2], "gold_frogs": 16}')
	var diagnostics := PackedStringArray()
	var restored: LevelProgress = LevelProgressSetup.from_dictionary(stack, data, diagnostics)
	assert_eq(diagnostics, PackedStringArray())
	assert_eq(restored.arcade_flags, PackedInt32Array([7, 6, 0, 2]))
	assert_eq(restored.arcade_levels[3], 19, "The jungle gold frog rewrites the row on load")

func test_loading_without_the_jungle_frog_keeps_jungle_one() -> void:
	var stack: LevelStack = LevelProgressSetup.stack_from_table(_table())
	var diagnostics := PackedStringArray()
	var restored: LevelProgress = LevelProgressSetup.from_dictionary(stack, {"arcade_flags": [6, 4, 0, 6], "gold_frogs": 0}, diagnostics)
	assert_eq(restored.arcade_levels[3], 18)
	assert_eq(restored.flags_of(18), S | Z)

func test_invalid_values_keep_fresh_flags_and_are_reported() -> void:
	var stack: LevelStack = LevelProgressSetup.stack_from_table(_table())
	var diagnostics := PackedStringArray()
	var restored: LevelProgress = LevelProgressSetup.from_dictionary(stack, {"arcade_flags": [7, "x", 8, -1, 6], "gold_frogs": 2.5}, diagnostics)
	assert_eq(restored.arcade_flags, PackedInt32Array([7, Z, 0, 0]))
	assert_eq(restored.gold_frogs, 0)
	assert_eq(diagnostics, PackedStringArray([
		"progress: 5 saved level words for 4 stack rows",
		"progress: level word 1 is not a flag set; kept the fresh flags",
		"progress: level word 2 is not a flag set; kept the fresh flags",
		"progress: level word 3 is not a flag set; kept the fresh flags",
		"progress: gold frogs missing or not a bit set; none collected",
	]))

func test_missing_data_gives_fresh_progress() -> void:
	var stack: LevelStack = LevelProgressSetup.stack_from_table(_table())
	var diagnostics := PackedStringArray()
	var restored: LevelProgress = LevelProgressSetup.from_dictionary(stack, {}, diagnostics)
	assert_eq(restored.arcade_flags, LevelProgress.create(stack).arcade_flags)
	assert_eq(diagnostics.size(), 2)
	var short: LevelProgress = LevelProgressSetup.from_dictionary(stack, {"arcade_flags": [7], "gold_frogs": 0}, diagnostics)
	assert_eq(short.arcade_flags, PackedInt32Array([7, Z, 0, 0]), "Rows without a saved word keep fresh flags")
