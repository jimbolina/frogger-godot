extends GutTest
## Synthetic frozen-C CheckCoordsInZones query outcomes.

const FIXTURE: String = "res://tests/golden/fixtures/zones_synthetic.json"
const GOLDEN: String = "res://tests/golden/synthetic/zones.tsv"

func test_source_ordered_synthetic_zone_queries() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(parsed is Dictionary)
	if not parsed is Dictionary:
		return
	var fixture: Dictionary = parsed
	var authored_zones: Array = fixture["zones"]
	var zones: Array[ZoneDefinition] = []
	for index: int in authored_zones.size():
		var input: Dictionary = authored_zones[index]
		var zone := ZoneDefinition.new()
		zone.zone_index = index
		var source_type: float = input["type"]
		zone.zone_type = int(source_type)
		zone.source_offset = 100 + index * 84
		var bounds: Array = input["bounds"]
		zone.bounds = PackedInt32Array(bounds)
		var regions: Array = input["regions"]
		for child: Array in regions:
			zone.regions.append(PackedInt32Array(child))
		zones.append(zone)
	var rows: PackedStringArray = FileAccess.get_file_as_string(GOLDEN).strip_edges().split("\n")
	assert_eq(rows.size(), 14)
	if rows.size() != 14:
		return
	var authored_queries: Array = fixture["queries"]
	for query_index: int in 13:
		var row: PackedStringArray = rows[query_index + 1].trim_suffix("\r").split("\t")
		var query: Array = authored_queries[query_index]
		var query_x: float = query[0]
		var query_z: float = query[1]
		var query_type: float = query[2]
		assert_eq(row.size(), 7)
		assert_eq(int(row[0]), query_index)
		assert_eq(int(row[1]), int(query_x))
		assert_eq(int(row[2]), int(query_z))
		assert_eq(int(row[3]), int(query_type))
		if int(query_type) == 0:
			var actual: int = ZoneQueries.first_camera_match(zones, Vector2i(int(query_x), int(query_z)))
			assert_eq(actual, int(row[5]), "Source ZONE query %d" % query_index)
			assert_eq(int(row[4]) == -1, actual >= 0, "Source TRUE is -1")
