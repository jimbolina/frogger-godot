extends GutTest
## Invented FORM contacts against independent Python and unchanged CollideFrog facts.

const FIXTURE: String = "res://tests/golden/fixtures/form_contacts.json"
const TRACE: String = "res://tests/golden/synthetic/form_contacts.tsv"

func _number(value: Variant) -> int:
	var number: float = value
	return int(number)

func _ints(values: Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	for value: Variant in values:
		result.append(_number(value))
	return result

func _case(defaults: Dictionary, changes: Dictionary) -> Dictionary:
	var result: Dictionary = defaults.duplicate(true)
	for key: Variant in changes:
		result[key] = changes[key]
	return result

func _definition(raw: Dictionary) -> FormContactDefinition:
	var definition := FormContactDefinition.new()
	definition.source_id = "synthetic"
	definition.entity_index = _number(raw["entity_index"])
	definition.unique_id = _number(raw["unique_id"])
	definition.form_grid_id = _number(raw["form_grid_id"])
	definition.form_id = _number(raw["form_id"])
	definition.form_name = str(raw["form_name"])
	definition.entity_flags = _number(raw["entity_flags"])
	var dimensions: Array = raw["dimensions"]
	definition.dimensions = Vector2i(_number(dimensions[0]), _number(dimensions[1]))
	var offsets: Array = raw["offsets"]
	definition.offsets = Vector2i(_number(offsets[0]), _number(offsets[1]))
	definition.height = _number(raw["height"])
	definition.max_y = _number(raw["max_y"])
	definition.radius_squared = _number(raw["radius_squared"])
	var flags: Array = raw["grid_flags"]
	definition.grid_flags = _ints(flags)
	return definition

func _observed(name: String, result: FormContactResult) -> PackedStringArray:
	return PackedStringArray([name, result.status, str(result.local_position.x),
		str(result.local_position.y), str(result.local_position.z), str(result.cell.x),
		str(result.cell.y), str(result.height), str(result.cell_flags)])

func test_independent_frozen_c_contact_gate_trace() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(parsed is Dictionary)
	if not parsed is Dictionary:
		return
	var fixture: Dictionary = parsed
	var defaults: Dictionary = fixture["defaults"]
	var cases: Array = fixture["cases"]
	var rows := PackedStringArray()
	for line: String in FileAccess.get_file_as_string(TRACE).split("\n", false):
		rows.append(line.trim_suffix("\r"))
	assert_eq(rows.size(), cases.size() + 1)
	for index: int in cases.size():
		var changes: Dictionary = cases[index]
		var raw: Dictionary = _case(defaults, changes)
		var definition: FormContactDefinition = _definition(raw)
		var entity := EntitySnapshot.new()
		entity.entity_index = definition.entity_index
		entity.unique_id = definition.unique_id
		var matrix: Array = raw["matrix12"]
		entity.matrix12 = _ints(matrix)
		var point: Array = raw["frog"]
		var result: FormContactResult = FormContactQuery.query(definition, entity,
			Vector3i(_number(point[0]), _number(point[1]), _number(point[2])))
		assert_eq(_observed(str(raw["name"]), result), rows[index + 1].split("\t"), str(raw["name"]))
