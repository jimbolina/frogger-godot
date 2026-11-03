extends GutTest
## The level support report of the local import maps every row of ORG1 and of
## every playable level.


func test_committed_org1_has_no_unmapped_rows() -> void:
	var data: ImportedAssets = ImportedAssets.open()
	assert_eq(data.error, "")
	var report: LevelSupportReport = LevelSupportReport.from_catalog(data, PackedStringArray(["ORG1"]))
	data.close()
	assert_eq(report.problems, PackedStringArray())
	assert_eq(_texts(report.unmapped()), PackedStringArray())
	assert_eq(report.level_count, 1)
	assert_gt(report.rows.size(), 0)


func test_committed_playable_levels_have_no_unmapped_rows() -> void:
	var data: ImportedAssets = ImportedAssets.open()
	assert_eq(data.error, "")
	var report: LevelSupportReport = LevelSupportReport.from_catalog(data)
	data.close()
	assert_eq(report.problems, PackedStringArray())
	assert_eq(_texts(report.unmapped()), PackedStringArray())
	assert_eq(report.level_count, 33)
	var unplaced := PackedStringArray()
	for row: LevelSupportReport.Row in report.unplaced():
		unplaced.append(row.kind + "|" + row.key)
	assert_has(unplaced, "callback|0x43CF20", "The Cave web-wall callback is placed by no map")


func _texts(rows: Array[LevelSupportReport.Row]) -> PackedStringArray:
	var texts := PackedStringArray()
	for row: LevelSupportReport.Row in rows:
		texts.append(row.to_tsv())
	return texts
