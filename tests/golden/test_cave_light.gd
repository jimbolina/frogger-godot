extends GutTest
## Independent cave omni-light facts through CaveLightShape: ranges, inner radii, energies and window-against-ramp samples.

const FACTS_PATH: String = "res://tests/golden/synthetic/cave_light.json"
const MODES: Dictionary[String, CaveLightShape.Mode] = {
	"exact_edge": CaveLightShape.Mode.EXACT_EDGE,
	"fitted_range": CaveLightShape.Mode.FITTED_RANGE,
}

var _facts: Dictionary = {}
var _tolerance: float = 0.0


func before_all() -> void:
	_facts = JSON.parse_string(FileAccess.get_file_as_string(FACTS_PATH))
	_tolerance = _facts["tolerance"]


func test_schema_and_constants() -> void:
	var schema: String = _facts["schema"]
	assert_eq(schema, "cave-light-v1")
	assert_eq(CaveLightShape.FIT_RINGS, _int(_facts["fit_rings"]), "fit_rings")
	assert_eq(CaveLightShape.FIT_REACH, _int(_facts["fit_reach"]), "fit_reach")
	assert_eq(CaveLightShape.SCALE_STEPS, _int(_facts["scale_steps"]), "scale_steps")
	assert_eq(CaveLightShape.BAND, _int(_facts["band"]), "band")


func test_fixtures_match_independent_facts() -> void:
	var fixtures: Array = _facts["fixtures"]
	assert_eq(fixtures.size(), 11)
	for fixture: Dictionary in fixtures:
		_check_fixture(fixture)


func _check_fixture(fixture: Dictionary) -> void:
	var fixture_name: String = fixture["name"]
	var min_r2: int = _int(fixture["min_r2"])
	var max_r2: int = _int(fixture["max_r2"])
	assert_almost_eq(CaveLightShape.inner_of(min_r2), _float(fixture["inner"]), _tolerance, fixture_name + " inner")
	var modes: Dictionary = fixture["modes"]
	for mode_name: String in MODES:
		var mode: CaveLightShape.Mode = MODES[mode_name]
		var expected: Dictionary = modes[mode_name]
		var label: String = "%s %s" % [fixture_name, mode_name]
		var reach: float = CaveLightShape.range_of(max_r2, mode)
		var energy: float = CaveLightShape.energy_of(min_r2, max_r2, mode)
		assert_almost_eq(reach, _float(expected["range"]), _tolerance, label + " range")
		assert_almost_eq(energy, _float(expected["energy"]), _tolerance, label + " energy")
		var samples: Array = expected["samples"]
		for sample: Dictionary in samples:
			var fraction: float = _float(sample["fraction"])
			var sample_label: String = "%s at %s" % [label, fraction]
			var window: float = CaveLightShape.window(fraction * reach, reach)
			assert_almost_eq(window, _float(sample["window"]), _tolerance, sample_label + " window")
			assert_almost_eq(energy * window, _float(sample["lit"]), _tolerance, sample_label + " lit")
			assert_almost_eq(CaveLightShape.ramp(_int(sample["distance_r2"]), min_r2, max_r2), _float(sample["ramp"]), _tolerance, sample_label + " ramp")


func _float(value: Variant) -> float:
	var result: float = value
	return result


func _int(value: Variant) -> int:
	var result: int = value
	return result
