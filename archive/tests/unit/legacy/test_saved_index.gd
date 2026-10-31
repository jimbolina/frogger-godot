extends GutTest
## A saved standalone MWI is checked without replacing the executable index.


func _index() -> MwiIndex:
	var index := MwiIndex.new()
	var entry := MwiEntry.new()
	entry.index = 0
	entry.path = "PACKED\\TEST.MAP"
	entry.sector_offset = 2
	entry.packed_size = 128
	entry.unpacked_size = 128
	index.entries.append(entry)
	return index


func test_saved_index_comparison_checks_semantic_entries() -> void:
	var embedded: MwiIndex = _index()
	var standalone: MwiIndex = _index()
	assert_eq(GameData.index_difference(embedded, standalone), "")
	standalone.entries[0].sector_offset = 3
	assert_true(GameData.index_difference(embedded, standalone).contains("entry 0"))
	assert_eq(embedded.entries[0].sector_offset, 2, "embedded authority is unchanged")


func test_saved_index_reports_missing_or_unreadable_entries() -> void:
	var standalone: MwiIndex = _index()
	standalone.entries.clear()
	assert_true(GameData.index_difference(_index(), standalone).contains("count"))
	standalone.error = "bad name pointer"
	assert_true(GameData.index_difference(_index(), standalone).contains("unreadable"))
