extends GutTest
## Level-select flag, completion, gold-frog and jungle rules over a stack shaped like retail's.

const C: int = LevelProgress.COMPLETED
const S: int = LevelProgress.SELECTABLE
const Z: int = LevelProgress.ZONE_ACCESSIBLE
const LEVELS: PackedInt32Array = [24, 25, 26, 27, 28, 48, 49, 50, 51, 52, 12, 13, 54, 56, 55, 0, 2, 3, 42, 44, 45, 43, 36, 39, 38, 37, 40, 6, 7, 8, 9, 10, 18]
const WORLDS: PackedInt32Array = [1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 4, 4, 5, 5, 5, 7, 7, 7, 3, 3, 3, 3, 2, 2, 2, 2, 2, 6, 6, 6, 6, 6, 8]
const THEMES: PackedInt32Array = [5, 5, 5, 5, 5, 9, 9, 9, 9, 9, 3, 3, 10, 10, 10, 1, 1, 1, 8, 8, 8, 8, 7, 7, 7, 7, 7, 2, 2, 2, 2, 2, 4]
const RACE_LEVELS: PackedInt32Array = [29, 53, 17, 59, 23]
const RACE_WORLDS: PackedInt32Array = [1, 0, 4, 5, 8]
const RACE_THEMES: PackedInt32Array = [5, 9, 3, 10, 4]

func _rows(levels: PackedInt32Array, worlds: PackedInt32Array, themes: PackedInt32Array) -> Array[LevelStack.Row]:
	var rows: Array[LevelStack.Row] = []
	for index: int in levels.size():
		var world: int = worlds[index]
		var local: int = 0
		for earlier: int in index:
			if worlds[earlier] == world:
				local += 1
		rows.append(LevelStack.Row.new(levels[index], world, 0, themes[index], local, worlds.count(world)))
	return rows

func _arcade_rows() -> Array[LevelStack.Row]:
	return _rows(LEVELS, WORLDS, THEMES)

func _stack() -> LevelStack:
	return LevelStack.create(_arcade_rows(), _rows(RACE_LEVELS, RACE_WORLDS, RACE_THEMES))

func _progress() -> LevelProgress:
	return LevelProgress.create(_stack())

func test_initial_flags_follow_select_level_init() -> void:
	var progress: LevelProgress = _progress()
	var expected: PackedInt32Array = PackedInt32Array()
	for level: int in LEVELS:
		if [24, 48, 12, 54].has(level):
			expected.append(S | Z)
		elif [25, 26, 27, 28, 49, 50, 51, 52, 13, 55, 56].has(level):
			expected.append(Z)
		else:
			expected.append(0)
	assert_eq(progress.arcade_flags, expected, "Only ORG1, SUB1, FOR1 and VOL1 open; their worlds are zone-accessible")
	assert_eq(progress.race_flags, PackedInt32Array([S | Z, S | Z, S | Z, S | Z, S | Z]), "Every race course opens")
	assert_eq(progress.gold_frogs, 0)
	assert_true(progress.is_selectable(24))
	assert_false(progress.is_selectable(25))
	assert_true(progress.is_zone_accessible(25))
	assert_false(progress.is_zone_accessible(0), "Caves stays closed")

func test_each_completion_in_stack_order_opens_the_next_level_of_its_world() -> void:
	for index: int in LEVELS.size():
		var progress: LevelProgress = _progress()
		var level: int = LEVELS[index]
		var result: LevelProgress.Completion = progress.complete_level(level)
		assert_true(result.found)
		assert_eq(progress.flags_of(level), C | S | Z, "%d is completed" % level)
		var last_of_world: bool = index + 1 == LEVELS.size() or WORLDS[index + 1] != WORLDS[index]
		assert_eq(result.zone_complete, last_of_world, "%d zone" % level)
		assert_eq(result.next_level, -1 if last_of_world else LEVELS[index + 1], "%d next" % level)
		if not last_of_world:
			assert_eq(progress.flags_of(result.next_level) & S, 0, "Startup alone does not open the next level")
			progress.open_level(result.next_level)
			assert_eq(progress.flags_of(result.next_level), S | Z)

func test_completion_does_not_open_the_next_level_until_the_page_leaves() -> void:
	var progress: LevelProgress = _progress()
	var result: LevelProgress.Completion = progress.complete_level(24)
	assert_eq(result.next_level, 25)
	assert_eq(progress.flags_of(25), Z)
	progress.open_level_if_closed(25)
	assert_eq(progress.flags_of(25), S | Z)

func test_count_down_reopening_clears_completed_but_triangle_keeps_it() -> void:
	var progress: LevelProgress = _progress()
	progress.complete_level(25)
	progress.open_level_if_closed(25)
	assert_eq(progress.flags_of(25), C | S | Z, "Triangle leaves a selectable level alone")
	progress.open_level(25)
	assert_eq(progress.flags_of(25), S | Z, "The count-down arm assigns the flags")

func test_last_level_of_each_world_finishes_the_zone() -> void:
	var progress: LevelProgress = _progress()
	for level: int in [28, 52, 13, 55, 3, 43, 40, 10]:
		var result: LevelProgress.Completion = progress.complete_level(level)
		assert_true(result.zone_complete, "%d ends its world" % level)
		assert_eq(result.next_level, -1)
		assert_false(result.jungle_rewritten)

func test_completing_jungle_one_at_the_stack_end_rewrites_the_row() -> void:
	var progress: LevelProgress = _progress()
	var result: LevelProgress.Completion = progress.complete_level(18)
	assert_true(result.zone_complete)
	assert_true(result.jungle_rewritten)
	assert_eq(progress.arcade_levels[32], 19)
	assert_eq(progress.arcade_flags[32], C | S | Z, "The rewritten row keeps its flags")
	assert_eq(progress.flags_of(18), C | S | Z, "JUN1 reads the jungle row")
	assert_false(progress.set_flags(18, 0), "JUN1 is no longer on the stack")

func test_level_missing_from_the_stack_is_ignored() -> void:
	var progress: LevelProgress = _progress()
	var before: PackedInt32Array = progress.arcade_flags.duplicate()
	var result: LevelProgress.Completion = progress.complete_level(1)
	assert_false(result.found)
	assert_eq(progress.arcade_flags, before)
	assert_eq(progress.flags_of(1), 0)
	assert_false(progress.set_flags(41, S))

func test_gold_frogs_open_the_first_closed_world_in_stack_order() -> void:
	var progress: LevelProgress = _progress()
	assert_eq(progress.collect_gold_frog(5), 0, "Caves opens first")
	assert_eq(progress.flags_of(0), S | Z)
	assert_eq(progress.flags_of(2), Z)
	assert_eq(progress.flags_of(3), Z)
	assert_eq(progress.collect_gold_frog(5), -1, "A collected frog opens nothing")
	assert_eq(progress.flags_of(42), 0)
	assert_eq(progress.collect_gold_frog(9), 42, "Sky")
	assert_eq(progress.flags_of(44), Z)
	assert_eq(progress.collect_gold_frog(3), 36, "Swamp")
	assert_eq(progress.collect_gold_frog(10), 6, "Desert")
	assert_eq(progress.collect_gold_frog(1), 18, "Jungle")
	assert_eq(progress.flags_of(18), S | Z)
	assert_eq(progress.collect_gold_frog(8), -1, "Every world is open")
	assert_eq(progress.gold_frogs, (1 << 5) | (1 << 9) | (1 << 3) | (1 << 10) | (1 << 1) | (1 << 8))
	assert_true(progress.has_gold_frog(8))
	assert_false(progress.has_gold_frog(4))
	assert_false(progress.has_all_gold_frogs())

func test_gold_frog_overwrites_only_rows_of_a_closed_theme() -> void:
	var progress: LevelProgress = _progress()
	progress.arcade_flags[16] = C
	assert_eq(progress.open_first_closed_world(), 0, "A completed but unselectable row does not open its theme")
	assert_eq(progress.arcade_flags[16], Z, "Zone access assigns over the old flags")

func test_gold_frog_display_moves_from_level_to_zone() -> void:
	var progress: LevelProgress = _progress()
	progress.start_game()
	progress.collect_gold_frog(5)
	var first: LevelProgress.Completion = progress.complete_level(24)
	assert_true(first.show_gold_frog)
	assert_eq(progress.gold_frogs_current, 0)
	assert_eq(progress.gold_frogs_zone, 1 << 5)
	var middle: LevelProgress.Completion = progress.complete_level(25)
	assert_false(middle.show_gold_frog)
	var last: LevelProgress.Completion = progress.complete_level(28)
	assert_true(last.show_gold_frog, "The zone-complete page shows a frog from earlier in the zone")
	assert_eq(progress.gold_frogs_zone, 0)

func test_gold_frog_found_on_the_last_level_shows_on_zone_complete() -> void:
	var progress: LevelProgress = _progress()
	progress.collect_gold_frog(5)
	var result: LevelProgress.Completion = progress.complete_level(28)
	assert_true(result.show_gold_frog)
	assert_eq(progress.gold_frogs_current, 0)
	assert_eq(progress.gold_frogs_zone, 0)

func test_start_game_flushes_only_the_current_game_bits() -> void:
	var progress: LevelProgress = _progress()
	progress.collect_gold_frog(5)
	progress.gold_frogs_zone = 1 << 9
	progress.start_game()
	assert_eq(progress.gold_frogs_current, 0)
	assert_eq(progress.gold_frogs_zone, 0)
	assert_eq(progress.gold_frogs, 1 << 5)

func test_jungle_statue_and_end_of_game_rewrite() -> void:
	var progress: LevelProgress = _progress()
	var flags_before: PackedInt32Array = progress.arcade_flags.duplicate()
	progress.reach_jungle_statue()
	assert_true(progress.has_gold_frog(4))
	assert_eq(progress.arcade_flags, flags_before, "The statue opens no world")
	assert_true(progress.rewrite_jungle_row())
	assert_eq(progress.arcade_levels[32], 19)
	assert_false(progress.rewrite_jungle_row(), "No JUN1 row remains")
	progress.apply_save_encoding()
	assert_eq(progress.arcade_flags[32], C | S | Z, "Saving marks the JUN2 row completed")

func test_save_encoding_without_jungle_two_changes_nothing() -> void:
	var progress: LevelProgress = _progress()
	var before: PackedInt32Array = progress.arcade_flags.duplicate()
	progress.apply_save_encoding()
	assert_eq(progress.arcade_flags, before)

func test_loaded_jungle_rule_follows_the_jungle_gold_frog() -> void:
	var progress: LevelProgress = _progress()
	progress.gold_frogs = 1 << 4
	progress.apply_loaded_jungle_rule()
	assert_eq(progress.arcade_levels[32], 19)
	progress.gold_frogs = 0
	progress.apply_loaded_jungle_rule()
	assert_eq(progress.arcade_levels[32], 18)

func test_initialise_resets_flags_but_keeps_row_levels() -> void:
	var progress: LevelProgress = _progress()
	progress.complete_level(18)
	progress.collect_gold_frog(5)
	progress.initialise()
	assert_eq(progress.arcade_levels[32], 19, "SelectLevelInit leaves the jungle row")
	assert_eq(progress.arcade_flags[15], 0)
	assert_eq(progress.arcade_flags[0], S | Z)
	assert_eq(progress.gold_frogs, 1 << 5, "Gold frogs are not part of SelectLevelInit")

func test_race_levels_use_the_race_stack() -> void:
	var progress: LevelProgress = _progress()
	assert_true(LevelProgress.is_race_level(29))
	assert_false(LevelProgress.is_race_level(24))
	assert_true(progress.set_flags(29, 0))
	assert_eq(progress.race_flags[0], 0)
	assert_eq(progress.flags_of(29), 0)
	assert_eq(progress.arcade_flags[0], S | Z, "Race writes leave the arcade stack")
	assert_false(progress.set_flags(5, S), "CAVM is not on the race stack")

func test_copy_is_complete_and_detached() -> void:
	var progress: LevelProgress = _progress()
	progress.collect_gold_frog(5)
	progress.complete_level(24)
	var duplicate: LevelProgress = progress.copy()
	assert_eq(duplicate.arcade_levels, progress.arcade_levels)
	assert_eq(duplicate.arcade_flags, progress.arcade_flags)
	assert_eq(duplicate.race_flags, progress.race_flags)
	assert_eq(duplicate.gold_frogs, progress.gold_frogs)
	assert_eq(duplicate.gold_frogs_zone, progress.gold_frogs_zone)
	duplicate.complete_level(18)
	duplicate.collect_gold_frog(9)
	duplicate.set_flags(29, 0)
	assert_eq(progress.arcade_levels[32], 18, "The source row is untouched")
	assert_eq(progress.flags_of(42), 0)
	assert_eq(progress.race_flags[0], S | Z)
	progress.initialise()
	assert_eq(duplicate.flags_of(24), C | S | Z, "The copy is untouched by the source")

func test_stack_rows_are_read_only_and_ordered() -> void:
	var stack: LevelStack = _stack()
	assert_eq(stack.arcade_count(), 33)
	assert_eq(stack.race_count(), 5)
	var row: LevelStack.Row = stack.arcade_row(13)
	assert_eq([row.level, row.world, row.theme, row.local_level, row.levels_in_world], [56, 5, 10, 1, 3])
	assert_eq(stack.arcade_index_of(55), 14)
	assert_eq(stack.race_index_of(23), 4)
	assert_eq(stack.arcade_index_of(99), -1)
	row.level = 7
	assert_eq(stack.arcade_row(13).level, 56, "Assignments do not change a row")
	var rows: Array[LevelStack.Row] = _arcade_rows()
	var shared: LevelStack = LevelStack.create(rows, [])
	rows.clear()
	assert_eq(shared.arcade_count(), 33, "The stack keeps its own row list")

func test_unlock_all_zones_opens_the_five_closed_worlds() -> void:
	var progress: LevelProgress = _progress()
	progress.unlock_all_zones()
	for level: int in [0, 42, 36, 6, 18]:
		assert_eq(progress.flags_of(level), S | Z, "%d opens" % level)
	for level: int in [2, 3, 43, 44, 45, 37, 38, 39, 40, 7, 8, 9, 10]:
		assert_eq(progress.flags_of(level), Z, "%d becomes zone-accessible" % level)
	assert_eq(progress.flags_of(24), S | Z, "ORG1 is untouched")
	assert_eq(progress.flags_of(25), Z, "ORG2 is untouched")
	assert_eq(progress.race_flags, PackedInt32Array([S | Z, S | Z, S | Z, S | Z, S | Z]))

func test_unlock_all_zones_assigns_the_first_levels_and_keeps_selectable_rows() -> void:
	var progress: LevelProgress = _progress()
	for level: int in [0, 42, 36, 6]:
		progress.complete_level(level)
	progress.arcade_flags[32] = C | S | Z
	progress.complete_level(2)
	progress.open_level_if_closed(2)
	progress.arcade_flags[17] = C
	progress.unlock_all_zones()
	for level: int in [0, 42, 36, 6, 18]:
		assert_eq(progress.flags_of(level), S | Z, "%d loses COMPLETED to the assignment" % level)
	assert_eq(progress.flags_of(2), C | S | Z, "A selectable CAV3 keeps its flags")
	assert_eq(progress.flags_of(3), Z, "A completed but closed CAV4 becomes zone-accessible only")

func test_unlock_all_levels_ors_both_bits_into_every_row() -> void:
	var progress: LevelProgress = _progress()
	progress.complete_level(24)
	progress.arcade_flags[16] = C
	progress.unlock_all_levels()
	for index: int in LEVELS.size():
		var expected: int = S | Z
		if index == 0 or index == 16:
			expected |= C
		assert_eq(progress.arcade_flags[index], expected, "row %d" % index)
	assert_eq(progress.race_flags, PackedInt32Array([S | Z, S | Z, S | Z, S | Z, S | Z]))

func test_unlocks_on_the_rewritten_jungle_row() -> void:
	var progress: LevelProgress = _progress()
	progress.complete_level(18)
	assert_eq(progress.arcade_levels[32], 19)
	progress.unlock_all_zones()
	assert_eq(progress.arcade_flags[32], C | S | Z, "The JUN1 write misses the JUN2 row")
	progress.arcade_flags[32] = C
	progress.unlock_all_levels()
	assert_eq(progress.arcade_flags[32], C | S | Z, "The level unlock reaches the JUN2 row")
