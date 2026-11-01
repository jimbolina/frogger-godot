extends GutTest
## The stack's lights come from the frozen-C stack light facts and the scene lights are built
## from that record.

const LAYOUT_GOLDEN: String = "res://tests/golden/synthetic/frontend_stack_layout.json"

var _lights: Array = []


func before_all() -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_GOLDEN))
	_lights = document["lights"]


static func _int(value: Variant) -> int:
	var number: float = value
	return int(number)


static func _stored(colour: Variant) -> Vector3:
	var items: Array = colour
	return Vector3(_int(items[0]), _int(items[1]), _int(items[2])) * 16.0


func test_lighting_is_the_golden_ambient_and_parallel_slots() -> void:
	var lighting: MapLighting = StackLighting.lighting()
	var ambient: Dictionary = _lights[0]
	assert_eq(str(ambient.type), "ambient")
	assert_eq(lighting.ambient, _stored(ambient.colour))
	assert_eq(lighting.directions.size(), _lights.size() - 1)
	assert_eq(lighting.colours.size(), _lights.size() - 1)
	for index: int in lighting.directions.size():
		var light: Dictionary = _lights[index + 1]
		var direction: Array = light.direction
		assert_eq(lighting.colours[index], _stored(light.colour), "slot %d" % index)
		assert_eq(lighting.directions[index], GameSpace.normal(_int(direction[0]), _int(direction[1]), _int(direction[2])), "slot %d" % index)
	assert_eq(lighting.ambient, Vector3(512, 512, 512))
	assert_eq(lighting.colours, [Vector3(1536, 1536, 1536), Vector3(1024, 1024, 1024), Vector3(768, 768, 768)] as Array[Vector3])


func test_modern_spec_has_three_lights_and_no_shadow_caster() -> void:
	var spec: SceneLightingSpec = SceneLightingBuilder.from_lighting(StackLighting.lighting(), false)
	assert_eq(spec.lights.size(), 3)
	assert_almost_eq(spec.ambient, Vector3.ONE * SceneLightingBuilder.gamma(512.0 / 4096.0), Vector3.ONE * 1e-6)
	for light: SceneLightingSpec.Light in spec.lights:
		assert_false(light.casts_shadow)
		assert_gt(light.energy, 0.0)
	assert_almost_eq(-spec.lights[2].basis.z, Vector3(0, 0, -1), Vector3.ONE * 1e-4, "light 2 travels along source +Z")
