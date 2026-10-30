extends GutTest
## Poly-piece pop pieces and motion against the poly_piece_pop family of tests/golden/synthetic/effects.json.

var _facts: Dictionary = {}

func before_all() -> void:
	_facts = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/effects.json"))

func _int(value: Variant) -> int:
	var result: int = value
	return result

func _vector(value: Variant) -> Vector3i:
	var values: Array = value
	return Vector3i(_int(values[0]), _int(values[1]), _int(values[2]))

func _vectors(value: Variant) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for item: Variant in value:
		result.append(_vector(item))
	return result

func _matrix(value: Variant) -> PackedInt32Array:
	var result := PackedInt32Array()
	for item: Variant in value:
		result.append(_int(item))
	return result

func test_poly_piece_pop_constants_match_independent_facts() -> void:
	var cases: Array = _facts["poly_piece_pop"]
	assert_gt(cases.size(), 0)
	for case: Dictionary in cases:
		var expected: Dictionary = case["expected"]
		assert_eq(PolyPiecePopState.DURATION, _int(expected["duration"]))
		assert_eq(PolyPiecePopState.WORLD_GRAVITY << 1, _int(expected["gravity_per_tick"]))
		assert_eq(PolyPiecePopState.ANGULAR_ACCELERATION, _vector(expected["angular_acceleration"]))

func test_poly_piece_pop_pieces_and_rows_match_independent_facts() -> void:
	var cases: Array = _facts["poly_piece_pop"]
	assert_gt(cases.size(), 0)
	for case: Dictionary in cases:
		var input: Dictionary = case["input"]
		var expected: Dictionary = case["expected"]
		var case_name: String = input["name"]
		var polygons: Array = input["polygons"]
		var pieces: Array = expected["pieces"]
		assert_eq(polygons.size(), pieces.size(), case_name)
		var origins: Array[Vector3i] = []
		for index: int in polygons.size():
			var piece: ModelPolyPieces.Piece = ModelPolyPieces.from_corners(_vectors(polygons[index]))
			var want: Dictionary = pieces[index]
			var label: String = "%s piece %d" % [case_name, index]
			assert_eq(piece.origin, _vector(want["origin"]), label + " origin")
			assert_eq(piece.vertices, _vectors(want["vertices"]), label + " vertices")
			origins.append(piece.origin)
		var state := PolyPiecePopState.new()
		state.start(_matrix(input["matrix"]), origins)
		assert_eq(state.timer, _int(expected["duration"]), case_name + " timer")
		for index: int in pieces.size():
			var want: Dictionary = pieces[index]
			var label: String = "%s piece %d" % [case_name, index]
			assert_eq(state.positions[index], _vector(want["position"]), label + " position")
			assert_eq(state.velocities[index], _vector(want["velocity"]), label + " velocity")
		var rows: Array = expected["rows"]
		assert_eq(rows.size(), _int(input["ticks"]), case_name + " rows")
		for row: Dictionary in rows:
			state.step()
			var label: String = "%s tick %d" % [case_name, _int(row["tick"])]
			assert_eq(state.timer, _int(row["timer"]), label + " timer")
			assert_eq(state.rotation, _vector(row["rotation"]), label + " rotation")
			assert_eq(state.angular_velocity, _vector(row["angular_velocity"]), label + " angular velocity")
			assert_eq(state.scale(), _int(row["scale"]), label + " scale")
			assert_eq(state.positions, _vectors(row["positions"]), label + " positions")
			var velocities_y: Array = row["velocities_y"]
			for index: int in velocities_y.size():
				assert_eq(state.velocities[index].y, _int(velocities_y[index]), "%s piece %d velocity y" % [label, index])
