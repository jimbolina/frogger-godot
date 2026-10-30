class_name LevelProgressSetup
extends RefCounted
## Builds the level-select stack from the executable's table and maps progress to plain data.
##
## The saved form follows retail's two progress values: one flag word per arcade row in stack
## order (co_selectable_levels) and the gold-frog bits (co_number_of_golden_frogs). Row levels
## are not saved; loading re-derives the jungle row from the gold frogs (LoadSave.c:3450-3476).

const ARCADE_FLAGS_KEY: String = "arcade_flags"
const GOLD_FROGS_KEY: String = "gold_frogs"
const FLAG_MASK: int = LevelProgress.COMPLETED | LevelProgress.SELECTABLE | LevelProgress.ZONE_ACCESSIBLE


## The arcade and race rows of [param table], in its order.
static func stack_from_table(table: LevelSelectTable) -> LevelStack:
	return LevelStack.create(_rows(table.arcade), _rows(table.race))


## The saved values of [param progress] as plain ints and an Array of ints.
static func to_dictionary(progress: LevelProgress) -> Dictionary:
	var flags: Array = []
	for value: int in progress.arcade_flags:
		flags.append(value)
	return {ARCADE_FLAGS_KEY: flags, GOLD_FROGS_KEY: progress.gold_frogs}


## Progress for [param stack] restored from [param data]. Rows without a valid saved word keep
## their fresh flags; every substitution is reported in [param diagnostics].
static func from_dictionary(stack: LevelStack, data: Dictionary, diagnostics: PackedStringArray) -> LevelProgress:
	var progress: LevelProgress = LevelProgress.create(stack)
	var saved: Variant = data.get(ARCADE_FLAGS_KEY, null)
	if saved is Array:
		var words: Array = saved
		if words.size() != progress.arcade_flags.size():
			diagnostics.append("progress: %d saved level words for %d stack rows" % [words.size(), progress.arcade_flags.size()])
		for index: int in mini(words.size(), progress.arcade_flags.size()):
			var word: int = _integer(words[index])
			if word < 0 or word & ~FLAG_MASK != 0:
				diagnostics.append("progress: level word %d is not a flag set; kept the fresh flags" % index)
			else:
				progress.arcade_flags[index] = word
	else:
		diagnostics.append("progress: no saved level words; kept the fresh flags")
	var gold: int = _integer(data.get(GOLD_FROGS_KEY, null))
	if gold < 0:
		diagnostics.append("progress: gold frogs missing or not a bit set; none collected")
	else:
		progress.gold_frogs = gold
	progress.apply_loaded_jungle_rule()
	return progress


static func _rows(entries: Array[LevelSelectEntry]) -> Array[LevelStack.Row]:
	var rows: Array[LevelStack.Row] = []
	for entry: LevelSelectEntry in entries:
		rows.append(LevelStack.Row.new(entry.level, entry.world, entry.stack_position,
			entry.theme, entry.local_level, entry.levels_in_world))
	return rows


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		var number: float = value
		if number >= 0.0 and number == floorf(number):
			return int(number)
	return -1
