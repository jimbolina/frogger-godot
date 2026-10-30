extends GutTest
## Poly-piece pop start, update, scale and drawing transform against
## hand-computed source values. Needs no game files.

const IDENTITY: Array[int] = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096]


func _matrix(rotation: Array[int], translation: Vector3i) -> PackedInt32Array:
	var result := PackedInt32Array(rotation)
	result.append_array(PackedInt32Array([translation.x, translation.y, translation.z]))
	return result


func test_start_places_pieces_and_aims_them_upward() -> void:
	var state := PolyPiecePopState.new()
	state.start(_matrix(IDENTITY, Vector3i(0x100, 0, 0)), [Vector3i.ZERO, Vector3i(0, 0x80, 0)] as Array[Vector3i])
	assert_eq(state.timer, 32)
	assert_eq(state.duration, 32)
	assert_eq(state.rotation, Vector3i.ZERO)
	assert_eq(state.angular_velocity, Vector3i.ZERO)
	assert_eq(state.piece_count(), 2)
	assert_eq(state.positions[0], Vector3i(0x100 << 16, 0, 0))
	assert_eq(state.velocities[0], Vector3i(0, -4096 * 1024, 0), "a centred piece flies straight up")
	assert_eq(state.positions[1], Vector3i(0x100 << 16, 0x80 << 16, 0))
	assert_eq(state.velocities[1], Vector3i.ZERO, "the zero direction stays zero")


func test_start_turns_origins_by_the_entity_matrix() -> void:
	var state := PolyPiecePopState.new()
	var quarter: Array[int] = [0, 0, 4096, 0, 4096, 0, -4096, 0, 0]
	state.start(_matrix(quarter, Vector3i(10, 20, 30)), [Vector3i(0x100, 0, 0)] as Array[Vector3i])
	assert_eq(state.positions[0], Vector3i(10 << 16, 20 << 16, (30 - 0x100) * 65536))
	assert_eq(state.velocities[0], Vector3i(0, -1832 * 1024, -3664 * 1024), "(0, -0x80, -0x100) normalised to 4096")


func test_step_follows_update_poly_piece_pop() -> void:
	var state := PolyPiecePopState.new()
	state.start(_matrix(IDENTITY, Vector3i.ZERO), [Vector3i.ZERO] as Array[Vector3i])
	state.step()
	assert_eq(state.timer, 31)
	assert_eq(state.rotation, Vector3i.ZERO)
	assert_eq(state.angular_velocity, Vector3i(8, 12, 16))
	assert_eq(state.velocities[0].y, -4194304 + 0x5b000)
	assert_eq(state.positions[0], Vector3i(0, -4194304 + 0x5b000, 0))
	state.step()
	assert_eq(state.rotation, Vector3i(8, 12, 16))
	assert_eq(state.angular_velocity, Vector3i(16, 24, 32))
	assert_eq(state.velocities[0].y, -4194304 + 2 * 0x5b000)
	assert_eq(state.positions[0].y, 2 * -4194304 + 3 * 0x5b000)


func test_scale_and_finish() -> void:
	var state := PolyPiecePopState.new()
	assert_eq(state.scale(), 0, "not started")
	state.start(_matrix(IDENTITY, Vector3i.ZERO), [Vector3i.ZERO] as Array[Vector3i])
	assert_eq(state.scale(), 0x1200)
	state.advance_to(18)
	assert_eq(state.timer, 18)
	assert_eq(state.scale(), 0x1200, "18 << 8 is the cap")
	state.advance_to(17)
	assert_eq(state.scale(), 17 << 8)
	state.advance_to(-5)
	assert_eq(state.timer, 0)
	assert_eq(state.scale(), 0)
	var rotation: Vector3i = state.rotation
	var position: Vector3i = state.positions[0]
	state.step()
	assert_eq(state.rotation, rotation, "a finished pop no longer moves")
	assert_eq(state.positions[0], position)


func test_rotation_order_is_x_then_y_then_z_composed_left_to_right() -> void:
	var state := PolyPiecePopState.new()
	state.start(_matrix(IDENTITY, Vector3i.ZERO), [Vector3i.ZERO] as Array[Vector3i])
	state.rotation = Vector3i(1024, 1024, 0)
	assert_eq(state.rotation_matrix().slice(0, 9), PackedInt32Array([0, 0, 4096, 4096, 0, 0, 0, 4096, 0]), "Rx(90) · Ry(90)")
	state.rotation = Vector3i(0, 0, 1024)
	state.lwtrans = PackedInt32Array([4096, 0, 0, 0, 0, -4096, 0, 4096, 0, 0, 0, 0])
	assert_eq(state.rotation_matrix().slice(0, 9), PackedInt32Array([0, 0, 4096, 4096, 0, 0, 0, 4096, 0]), "Rz(90) · lwtrans")


func test_transform_scales_the_turned_entity_matrix_at_the_whole_unit_position() -> void:
	var state := PolyPiecePopState.new()
	state.start(_matrix(IDENTITY, Vector3i(0x100, -0x200, 0x80)), [Vector3i.ZERO] as Array[Vector3i])
	state.positions[0] = Vector3i((0x100 << 16) + 0xffff, -0x200 * 65536, 0x80 << 16)
	var at: Transform3D = state.transform_for(0)
	assert_eq(at.origin, Vector3(1, 2, -0.5), "the source drops the 16-bit fraction")
	assert_almost_eq(at.basis.x, Vector3(1.125, 0, 0), Vector3.ONE * 0.0001)
	assert_almost_eq(at.basis.y, Vector3(0, 1.125, 0), Vector3.ONE * 0.0001)
	assert_almost_eq(at.basis.z, Vector3(0, 0, 1.125), Vector3.ONE * 0.0001)
	state.rotation = Vector3i(0, 1024, 0)
	var turned: Basis = state.basis()
	var game: Vector3 = turned * GameSpace.position(0x100, 0, 0)
	assert_almost_eq(game, GameSpace.position(0, 0, -0x100) * 1.125, Vector3.ONE * 0.0001, "Ry(90) takes game +x to game -z")
