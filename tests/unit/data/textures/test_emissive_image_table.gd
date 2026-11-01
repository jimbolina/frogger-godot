extends GutTest
## The glowing-image table finds entries by name in any case and reports
## unusable entries.


func test_find_ignores_case_and_returns_null_when_absent() -> void:
	var table: EmissiveImageTable = _table([_entry("vol_lava6", 1.5, 1.0), _entry("VOL_HotRock1", 0.5, 0.0)])
	assert_eq(table.find("vol_lava6"), table.entries[0])
	assert_eq(table.find("VOL_LAVA6"), table.entries[0])
	assert_eq(table.find("vol_hotrock1"), table.entries[1])
	assert_null(table.find("vol_lava7"))
	assert_null(table.find(""))
	assert_null(EmissiveImageTable.new().find("vol_lava6"))


func test_a_well_formed_table_validates() -> void:
	assert_eq(_table([_entry("vol_lava6", 1.5, 1.0), _entry("vol_lava7", 0.0, 0.0)]).validate(), PackedStringArray())
	assert_eq(EmissiveImageTable.new().validate(), PackedStringArray())


func test_validate_reports_each_problem() -> void:
	var table: EmissiveImageTable = _table([
		_entry("vol_lava6", 1.5, 1.0),
		_entry("VOL_LAVA6", 1.0, 1.0),
		_entry(" ", 1.0, 1.0),
		_entry("vol_lava7", -0.5, 1.0),
		_entry("vol_lava5", 1.0, -1.0),
	])
	table.entries.append(null)
	var problems: PackedStringArray = table.validate()
	assert_eq(problems.size(), 5, "\n".join(problems))
	assert_string_contains(problems[0], "repeats VOL_LAVA6")
	assert_string_contains(problems[1], "entry 2 has no image name")
	assert_string_contains(problems[2], "vol_lava7 has negative strength")
	assert_string_contains(problems[3], "vol_lava5 has negative light energy")
	assert_string_contains(problems[4], "entry 5 is empty")


func _table(entries: Array[EmissiveImage]) -> EmissiveImageTable:
	var table := EmissiveImageTable.new()
	table.entries = entries
	return table


func _entry(image_name: String, strength: float, energy: float) -> EmissiveImage:
	var entry := EmissiveImage.new()
	entry.image_name = image_name
	entry.strength = strength
	entry.light_energy = energy
	entry.light = energy > 0.0
	return entry
