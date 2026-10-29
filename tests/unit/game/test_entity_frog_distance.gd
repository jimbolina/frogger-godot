extends GutTest
## Hand-derived frozen DistanceToFrogger point transform, narrowing and frog gate.

const YAW_90: PackedInt32Array = [0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 100, 0, 200]

func _frog(position: Vector3i, flags: int = FrogFlags.ACTIVE) -> GameplayState:
	var state := GameplayState.new()
	state.frog.flags = flags
	state.frog.matrix12[9] = position.x
	state.frog.matrix12[10] = position.y
	state.frog.matrix12[11] = position.z
	return state

func test_local_offset_is_rotated_before_translation() -> void:
	assert_eq(EntityFrogDistance.distance(YAW_90, Vector3i(0, 0, 256), _frog(Vector3i(386, 40, 200))), 50)
	assert_eq(EntityFrogDistance.distance(YAW_90, Vector3i(256, 0, 0), _frog(Vector3i(100, 0, -56))), 0)
	assert_eq(EntityFrogDistance.distance(YAW_90, Vector3i.ZERO, _frog(Vector3i(103, 4, 200))), 5)

func test_point_and_difference_narrow_to_signed_shorts() -> void:
	var matrix: PackedInt32Array = YAW_90.duplicate()
	matrix[9] = 32767
	assert_eq(EntityFrogDistance.distance(matrix, Vector3i(0, 0, 256), _frog(Vector3i(-32513, 0, 200))), 0)
	assert_eq(EntityFrogDistance.distance(EntityTransform.IDENTITY, Vector3i.ZERO, _frog(Vector3i(65536 + 3, 4, 0))), 5)

func test_only_an_active_frog_is_measured() -> void:
	assert_eq(EntityFrogDistance.distance(YAW_90, Vector3i.ZERO, null), 9999999)
	assert_eq(EntityFrogDistance.distance(YAW_90, Vector3i.ZERO, _frog(Vector3i(100, 0, 200), FrogFlags.CONTROL_ACTIVE)), 9999999)
	assert_eq(EntityFrogDistance.distance(YAW_90, Vector3i.ZERO, _frog(Vector3i(100, 0, 200), FrogFlags.ACTIVE)), 0)
