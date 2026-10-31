extends GutTest
## Independent scene lighting facts from synthetic C light records through MapLighting and SceneLightingBuilder.

const FACTS_PATH: String = "res://tests/golden/synthetic/scene_lighting.json"

var _facts: Dictionary = {}
var _tolerance: float = 0.0


func before_all() -> void:
	_facts = JSON.parse_string(FileAccess.get_file_as_string(FACTS_PATH))
	_tolerance = _facts["tolerance"]


func test_schema_and_constants() -> void:
	var schema: String = _facts["schema"]
	assert_eq(schema, "scene-lighting-v1")
	assert_eq(SceneLightingBuilder.GAMMA, _float(_facts["gamma"]), "gamma")
	assert_eq(SceneLightingBuilder.LAMBERT_SCALE, _float(_facts["lambert_scale"]), "lambert_scale")


func test_fixtures_match_independent_facts() -> void:
	var fixtures: Array = _facts["fixtures"]
	assert_eq(fixtures.size(), 10)
	for fixture: Dictionary in fixtures:
		_check_fixture(fixture)


func _check_fixture(fixture: Dictionary) -> void:
	var fixture_name: String = fixture["name"]
	var expected: Dictionary = fixture["expected"]
	var rows: Array = fixture["lights"]
	var shadows: bool = fixture["shadows"]
	var ambient: Array = expected["ambient"]
	var lighting := MapLighting.new()
	lighting.configure(_records(rows))
	var spec: SceneLightingSpec = SceneLightingBuilder.from_lighting(lighting, shadows)
	assert_eq(spec.shadows, shadows, "%s shadows" % fixture_name)
	_assert_vector(spec.ambient, ambient, "%s ambient" % fixture_name)
	var slots: Array = expected["slots"]
	assert_eq(spec.lights.size(), slots.size(), "%s slot count" % fixture_name)
	if spec.lights.size() != slots.size():
		return
	var caster: int = -1
	for index: int in slots.size():
		var slot: Dictionary = slots[index]
		var light: SceneLightingSpec.Light = spec.lights[index]
		var label: String = "%s slot %d" % [fixture_name, index]
		var forward: Array = slot["forward"]
		_assert_vector(light.basis * Vector3.FORWARD, forward, label + " forward")
		var colour: Array = slot["colour"]
		_assert_vector(Vector3(light.colour.r, light.colour.g, light.colour.b), colour, label + " colour")
		assert_almost_eq(light.energy, _float(slot["energy"]), _tolerance, label + " energy")
		if light.casts_shadow:
			assert_eq(caster, -1, label + " second caster")
			caster = index
	assert_eq(caster, _int(expected["caster"]), "%s caster" % fixture_name)


func _records(rows: Array) -> Array[MapLight]:
	var lights: Array[MapLight] = []
	for row: Dictionary in rows:
		var colour: Array = row["colour"]
		var direction: Array = row["direction"]
		var light := MapLight.new()
		light.light_type = _int(row["light_type"])
		light.category = _int(row["category"])
		light.enabled = light.category == 1
		light.color = Color8(_int(colour[0]), _int(colour[1]), _int(colour[2]))
		light.direction = Vector3i(_int(direction[0]), _int(direction[1]), _int(direction[2]))
		lights.append(light)
	return lights


func _assert_vector(actual: Vector3, expected: Array, label: String) -> void:
	var target := Vector3(_float(expected[0]), _float(expected[1]), _float(expected[2]))
	assert_true(absf(actual.x - target.x) <= _tolerance and absf(actual.y - target.y) <= _tolerance
		and absf(actual.z - target.z) <= _tolerance, "%s: %s against %s" % [label, actual, target])


func _float(value: Variant) -> float:
	var result: float = value
	return result


func _int(value: Variant) -> int:
	var result: int = value
	return result
