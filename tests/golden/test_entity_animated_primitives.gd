extends GutTest
## Invented animated-part cuboid contacts and source rotation-cache sequences
## from tools/make_golden_entity_animated_primitives.py.

const IDENTITY_ROTATION: PackedInt32Array = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096]

var _document: Dictionary = {}

func before_all() -> void:
	_document = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/entity_animated_primitives.json"))

func _ints(value: Variant) -> PackedInt32Array:
	var items: Array = value
	var result := PackedInt32Array()
	for item: Variant in items:
		var number: float = item
		result.append(int(number))
	return result

func _vector(value: Variant) -> Vector3i:
	var values: PackedInt32Array = _ints(value)
	return Vector3i(values[0], values[1], values[2])

func _primitive(value: Variant) -> EntityPrimitiveDefinition:
	var record: Dictionary = value
	var result := EntityPrimitiveDefinition.new()
	var matrix: PackedInt32Array = _ints(record["matrix"])
	result.part_index = 4
	result.offset = _vector(record["offset"])
	result.half_size = _vector(record["half_size"])
	result.flags = _ints([record["flags"]])[0]
	if not matrix.is_empty():
		result.matrix_index = 0
		result.rotation = matrix.slice(0, 9)
	return result

func _probe(point: Vector3i) -> FrogCollisionQuery.Sample:
	var result := FrogCollisionQuery.Sample.new()
	result.points.append(point)
	result.part_indices.append(0)
	result.hilite_indices.append(0)
	return result

func _key(value: Variant) -> String:
	var items: Array = value
	var parts := PackedStringArray()
	for item: Variant in items:
		if item is float:
			var number: float = item
			parts.append(str(int(number)))
		else:
			parts.append(str(item))
	return ":".join(parts)

func test_document_shape() -> void:
	assert_eq(str(_document.get("schema", "")), "entity-animated-primitives-v1")
	var cases: Array = _document.get("cases", [])
	var sequences: Array = _document.get("sequences", [])
	assert_eq(cases.size(), 67)
	assert_eq(sequences.size(), 5)

func test_stored_lw_part_frames_and_matrix_rotations() -> void:
	for item: Variant in _document.get("cases", []):
		var fixture: Dictionary = item
		var label: String = str(fixture["name"])
		var expected: Dictionary = fixture["expected"]
		var frog := FrogCollisionDefinition.new()
		frog.part_count = 1
		var probe := FrogCollisionDefinition.Probe.new()
		probe.vertex = _vector(fixture["vertex"])
		frog.probes.append(probe)
		var frog_action := FrogCollisionDefinition.Action.new()
		frog_action.actual_cels = PackedInt32Array([0])
		frog_action.frames.append(_ints(fixture["frog_part"]))
		frog.actions.append(frog_action)
		var sample: FrogCollisionQuery.Sample = FrogCollisionQuery.sample(frog, 0, 0, _ints(fixture["frog_root"]))
		assert_eq(sample.error, "", label)
		if not sample.error.is_empty():
			continue
		assert_eq(sample.points[0], _vector(expected["world"]), label + " frog point")
		var part := EntityPrimitivePartDefinition.new()
		part.part_index = 4
		var action := EntityPrimitivePartDefinition.Action.new()
		action.frames.append(_ints(fixture["part_frame"]))
		action.actual_cels = PackedInt32Array([0])
		part.actions.append(action)
		assert_eq(part.validate(), "", label)
		var animation: EntityAnimationState = EntityAnimationState.create(PackedInt32Array([1]))
		animation.cel = 0
		var pose := EntityPrimitivePose.new()
		assert_eq(pose.refresh(part, animation, _ints(fixture["entity_root"])), "", label)
		assert_eq(pose.lw12, _ints(expected["lw"]), label + " stored LW")
		var primitive: EntityPrimitiveDefinition = _primitive(fixture["primitive"])
		assert_eq(primitive.validate(), "", label)
		var rotation: PackedInt32Array = EntityPrimitiveQuery.collision_rotation(pose.lw12, primitive)
		assert_eq(rotation, _ints(expected["rotation"]), label + " collision rotation")
		var primitives: Array[EntityPrimitiveDefinition] = [primitive]
		var result: EntityPrimitiveQuery.Result = EntityPrimitiveQuery.query(primitives, pose.lw12, sample, rotation)
		var hit: bool = expected["hit"]
		assert_eq(result.status == EntityPrimitiveQuery.CONTACT, hit, label + " hit")
		if hit:
			assert_eq(result.local_position, _vector(expected["local"]), label + " local")
		if primitive.flags & EntityPrimitiveDefinition.DISABLED:
			assert_eq(result.status, EntityPrimitiveQuery.DISABLED, label)
			continue
		var wide: EntityPrimitiveDefinition = primitive.copy()
		wide.half_size = Vector3i(65535, 65535, 65535)
		var delta: EntityPrimitiveQuery.Result = EntityPrimitiveQuery.query([wide], pose.lw12, sample, IDENTITY_ROTATION)
		assert_eq(delta.local_position, _vector(expected["delta"]), label + " short offset")
		var local: EntityPrimitiveQuery.Result = EntityPrimitiveQuery.query([wide], pose.lw12, sample, rotation)
		assert_eq(local.local_position, _vector(expected["local"]), label + " local vector")

func test_rotation_cache_sequences() -> void:
	for item: Variant in _document.get("sequences", []):
		var sequence: Dictionary = item
		var cache := CollisionTransposeCache.new()
		var checks: Array = sequence["checks"]
		for index: int in checks.size():
			var check: Dictionary = checks[index]
			var label: String = "%s check %d" % [sequence["name"], index]
			var expected: Dictionary = check["expected"]
			var frame: PackedInt32Array = _ints(check["frame"])
			var primitive: EntityPrimitiveDefinition = _primitive(check["primitive"])
			var primitives: Array[EntityPrimitiveDefinition] = [primitive]
			var probes: FrogCollisionQuery.Sample = _probe(_vector(check["point"]))
			var rotation := PackedInt32Array()
			if not primitive.flags & EntityPrimitiveDefinition.DISABLED:
				rotation = cache.resolve(_key(check["frame_key"]), _key(check["matrix_key"]), frame, primitive)
				assert_eq(rotation, _ints(expected["rotation"]), label + " cached rotation")
			var result: EntityPrimitiveQuery.Result = EntityPrimitiveQuery.query(primitives, frame, probes, rotation)
			assert_eq(result.status, str(expected["status"]), label + " status")
			if result.status == EntityPrimitiveQuery.CONTACT:
				assert_eq(result.local_position, _vector(expected["local"]), label + " local")
