extends GutTest
## Hand-derived frozen UpdateEntityWithVelocity gravity, wrap and shift order.

func _entity(flags: int = 0) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.entity_flags = flags
	entity.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 7, 8, 9])
	return entity

func test_gravity_is_added_before_position_integration() -> void:
	var entity: EntitySnapshot = _entity()
	var custom := EntityCustomState.new()
	custom.offset_16 = Vector3i(100 << 16, 200 << 16, -1)
	custom.velocity_16 = Vector3i(0x10000, -0x50000, -0x10000)
	EntityVelocity.step(entity, custom)
	assert_eq(custom.velocity_16, Vector3i(0x10000, -0x22800, -0x10000))
	assert_eq(custom.offset_16, Vector3i(101 << 16, (200 << 16) - 0x22800, -0x10001))
	assert_eq(entity.matrix12.slice(9), PackedInt32Array([101, 197, -2]))
	assert_eq(entity.matrix12.slice(0, 9), PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096]))

func test_components_wrap_as_signed_32_bit() -> void:
	var entity: EntitySnapshot = _entity()
	var custom := EntityCustomState.new()
	custom.offset_16 = Vector3i(0x7fff0000, 0, 0)
	custom.velocity_16 = Vector3i(0x20000, 0x7fffffff, 0)
	EntityVelocity.step(entity, custom)
	var wrapped: int = 0x7fffffff + 0x2d800 - 0x100000000
	assert_eq(custom.velocity_16.y, wrapped)
	assert_eq(custom.offset_16.x, 0x80010000 - 0x100000000)
	assert_eq(entity.matrix12[9], -32767)
	assert_eq(entity.matrix12[10], wrapped >> 16)
	assert_eq(entity.matrix12[10], -32766)

func test_no_movement_leaves_velocity_position_and_matrix() -> void:
	var entity: EntitySnapshot = _entity(EntityDefinition.NO_MOVEMENT)
	var custom := EntityCustomState.new()
	custom.offset_16 = Vector3i(1, 2, 3)
	custom.velocity_16 = Vector3i(4, 5, 6)
	EntityVelocity.step(entity, custom)
	assert_eq(custom.offset_16, Vector3i(1, 2, 3))
	assert_eq(custom.velocity_16, Vector3i(4, 5, 6))
	assert_eq(entity.matrix12.slice(9), PackedInt32Array([7, 8, 9]))
