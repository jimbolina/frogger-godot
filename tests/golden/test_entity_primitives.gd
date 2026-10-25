extends GutTest
## Invented probe/cuboid facts independently checked against linked frozen C.

func _vector(value: Array) -> Vector3i:
	var x: float = value[0]
	var y: float = value[1]
	var z: float = value[2]
	return Vector3i(int(x), int(y), int(z))

func test_independent_animated_probe_and_cuboid_cases() -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/entity_primitives.json"))
	assert_eq(str(document.get("schema", "")), "entity-primitives-v1")
	var cases: Array = document.get("cases", [])
	assert_eq(cases.size(), 68)
	for item: Variant in cases:
		var fixture: Dictionary = item
		var label: String = str(fixture["name"])
		var vertex: Array = fixture["vertex"]
		var part: Array = fixture["part"]
		var root: Array = fixture["root"]
		var owner: Array = fixture["owner"]
		var offset: Array = fixture["offset"]
		var half_size: Array = fixture["half_size"]
		var flags: float = fixture["flags"]
		var reaction: float = fixture["reaction"]
		var definition := FrogCollisionDefinition.new()
		definition.part_count = 1
		var probe := FrogCollisionDefinition.Probe.new()
		probe.vertex = _vector(vertex)
		definition.probes.append(probe)
		var action := FrogCollisionDefinition.Action.new()
		action.actual_cels = PackedInt32Array([0])
		action.frames.append(PackedInt32Array(part))
		definition.actions.append(action)
		assert_eq(definition.validate(), "", label)
		var sample: FrogCollisionQuery.Sample = FrogCollisionQuery.sample(definition, 0, 0, PackedInt32Array(root))
		assert_eq(sample.error, "", label)
		if not sample.error.is_empty() or sample.points.is_empty():
			continue
		var expected: Dictionary = fixture["expected"]
		var expected_world: Array = expected["world"]
		var expected_hit: bool = expected["hit"]
		assert_eq(sample.points[0], _vector(expected_world), label + " stored-LW world point")
		var primitive := EntityPrimitiveDefinition.new()
		primitive.offset = _vector(offset)
		primitive.half_size = _vector(half_size)
		primitive.flags = int(flags)
		primitive.reaction = int(reaction)
		var result: EntityPrimitiveQuery.Result = EntityPrimitiveQuery.query([primitive], PackedInt32Array(owner), sample)
		assert_eq(result.status == EntityPrimitiveQuery.CONTACT, expected_hit, label + " cuboid hit")
		assert_true(result.status in [EntityPrimitiveQuery.CONTACT, EntityPrimitiveQuery.MISS, EntityPrimitiveQuery.DISABLED], label + " supported result")
