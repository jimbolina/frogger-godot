extends RetailTest
## Retail decoded demo headers and complete input-buffer summaries.


func test_demo_headers_and_input_summaries_match_independent_facts() -> void:
	var version: GameVersionConfig = FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e")
	var data: GameData = GameData.open(retail_source(), version)
	assert_eq(data.error, "")
	if not data.is_valid():
		return
	var problems := PackedStringArray()
	var got: Array[PackedStringArray] = RetailFactRows.demo_rows(data, problems)
	data.close()
	assert_eq(problems.size(), 0, "\n".join(problems))
	var differences: PackedStringArray = GoldenFiles.differences("demos", got, GoldenFiles.rows("demos.tsv"))
	assert_eq(differences.size(), 0, "\n".join(differences))
