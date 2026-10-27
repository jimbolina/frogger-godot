extends GutTest
## Independent frozen tongue clocks and recursively updated Bezier targets.

func _vector(values: Array) -> Vector3i:
	var x: int = values[0]
	var y: int = values[1]
	var z: int = values[2]
	return Vector3i(x, y, z)

func test_independent_tongue_facts() -> void:
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/tongue.json"))
	var schema: String = facts.schema
	assert_eq(schema, "tongue-v1")
	for value: Dictionary in facts.cases:
		var tongue := TongueState.new()
		var has_target: bool = value.target != null
		var target_values: Array = value.target if has_target else [0, 0, 0]
		var target: Vector3i = _vector(target_values)
		var matrix_values: Array = value.matrix
		var matrix := PackedInt32Array(matrix_values)
		tongue.start(7 if has_target else -1)
		for row: Dictionary in value.rows:
			var active: bool = tongue.mode != TongueState.Mode.IDLE
			var collected: int = tongue.advance()
			if active:
				tongue.tip = TongueCurve.tip(matrix, tongue.section, target, has_target)
				if has_target and (tongue.mode == TongueState.Mode.IN or collected >= 0):
					target = tongue.tip
			var expected_mode: int = row.mode
			var expected_section: int = row.section
			var expected_counter: int = row.counter
			var expected_collected: bool = row.collected
			assert_eq(int(tongue.mode), expected_mode, str(value.name))
			assert_eq(tongue.section, expected_section, str(value.name))
			assert_eq(tongue.counter, expected_counter, str(value.name))
			assert_eq(collected >= 0, expected_collected, str(value.name))
			var expected_tip: Array = row.tip
			assert_eq(tongue.tip, _vector(expected_tip), "%s tick %d" % [value.name, row.tick])
