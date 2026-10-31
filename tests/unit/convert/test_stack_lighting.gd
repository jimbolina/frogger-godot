extends GutTest
## The stack's lights come from the frozen-C stack light facts, the retail box materials read
## exactly those values and the modern scene lights are built from the same record.

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


func test_retail_box_material_reads_the_same_lights_at_the_neutral_tint() -> void:
	var material: ShaderMaterial = StackMeshBuilder.box_material(null, StackMeshBuilder.NEUTRAL_COLOUR)
	var lighting: MapLighting = StackLighting.lighting()
	var ambient: Vector3 = material.get_shader_parameter("source_ambient")
	assert_eq(ambient, Vector3(512, 512, 512))
	assert_eq(ambient, lighting.ambient)
	var pinned: Array[Vector3] = [Vector3(1536, 1536, 1536), Vector3(1024, 1024, 1024), Vector3(768, 768, 768)]
	for index: int in lighting.directions.size():
		var colour: Vector3 = material.get_shader_parameter("source_colour%d" % index)
		var direction: Vector3 = material.get_shader_parameter("source_direction%d" % index)
		assert_eq(colour, pinned[index], "slot %d" % index)
		assert_eq(colour, lighting.colours[index], "slot %d" % index)
		assert_eq(direction, lighting.directions[index], "slot %d" % index)


func test_modern_spec_has_three_lights_and_no_shadow_caster() -> void:
	var spec: SceneLightingSpec = SceneLightingBuilder.from_lighting(StackLighting.lighting(), false)
	assert_eq(spec.lights.size(), 3)
	assert_almost_eq(spec.ambient, Vector3.ONE * SceneLightingBuilder.gamma(512.0 / 4096.0), Vector3.ONE * 1e-6)
	for light: SceneLightingSpec.Light in spec.lights:
		assert_false(light.casts_shadow)
		assert_gt(light.energy, 0.0)
	assert_almost_eq(-spec.lights[2].basis.z, Vector3(0, 0, -1), Vector3.ONE * 1e-4, "light 2 travels along source +Z")
