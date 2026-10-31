extends RetailTest
## Retail decoded demo headers and complete input-buffer summaries.


func test_demo_headers_and_input_summaries_match_independent_facts() -> void:
	var version: GameVersionConfig = FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e")
	var data: GameData = GameData.open(retail_source(), version)
	assert_eq(data.error, "")
	if not data.is_valid():
		return
	var got: Array[PackedStringArray] = []
	for low: bool in [true, false]:
		for entry: DemoTable.Entry in data.tables.demo_table().entries:
			if entry.is_skipped():
				continue
			var rid: int = entry.demo_id(low)
			var problems := PackedStringArray()
			var demo: SourceDemoFile = SourceDemoFileReader.parse(data.read_resource(rid, problems), "resource %d" % rid)
			assert_eq(problems.size(), 0)
			assert_eq(demo.error, "")
			var values := PackedInt64Array()
			var counts := PackedInt32Array()
			counts.resize(10)
			for byte: int in demo.input_bytes:
				values.append(byte)
				if byte & 128:
					counts[0] += 1
				else:
					counts[1 + (byte & 3)] += 1
				for bit: int in range(2, 7):
					if byte & (1 << bit):
						counts[3 + bit] += 1
			var row := PackedStringArray(["low" if low else "high", str(entry.level), str(rid), str(demo.duration),
				str(demo.start_grid_x), str(demo.start_grid_z), str(values.size()), GoldenFiles.list_digest(values)])
			for count: int in counts:
				row.append(str(count))
			got.append(row)
	data.close()
	var differences: PackedStringArray = GoldenFiles.differences("demos", got, GoldenFiles.rows("demos.tsv"))
	assert_eq(differences.size(), 0, "\n".join(differences))
