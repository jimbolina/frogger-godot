extends RetailTest
## Every final-PC entity identity and generic base record against independent facts.

var _data: GameData

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func test_all_entity_identity_base_records_and_setup_census() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("entities_retail.tsv")
	rows.pop_front()
	assert_eq(rows.size(), 78)
	var problems := PackedStringArray()
	for row: PackedStringArray in rows:
		var actual: PackedStringArray = RetailFactRows.entity_row(_data, int(row[0]), problems)
		assert_eq(actual, row, row[1])
	assert_eq(problems.size(), 0, "\n".join(problems))
