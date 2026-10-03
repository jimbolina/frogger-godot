extends GutTest
## Camera attachment and turn state shared by platform movement and collision.

const IDENTITY: PackedInt32Array = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]
const QUARTER_TURN: PackedInt32Array = [0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 40, 0, -60]

func _camera() -> GameplayCamera:
	return GameplayCamera.create(GameplayCameraDefinition.new(), Vector3i.ZERO)

func test_attachment_rotation_is_removed_on_departure() -> void:
	var camera: GameplayCamera = _camera()
	assert_eq(camera.error, "")
	assert_eq(camera.transition_attachment(PackedInt32Array(), QUARTER_TURN, true), "")
	var attached: GameplayCameraSnapshot = camera.snapshot()
	assert_eq(attached.mod_matrix12.size(), 12)
	assert_ne(attached.mod_matrix12.slice(0, 9), IDENTITY.slice(0, 9))
	assert_eq(attached.mod_matrix12[9], 0)
	assert_eq(attached.mod_matrix12[10], 0)
	assert_eq(attached.mod_matrix12[11], 0)
	assert_eq(camera.transition_attachment(QUARTER_TURN, PackedInt32Array(), true), "")
	assert_eq(camera.snapshot().mod_matrix12, IDENTITY)

func test_attachment_copy_and_invalid_matrix_do_not_mutate_camera() -> void:
	var camera: GameplayCamera = _camera()
	assert_eq(camera.transition_attachment(PackedInt32Array(), QUARTER_TURN, false), "")
	var before: GameplayCameraSnapshot = camera.snapshot()
	var detached: GameplayCameraSnapshot = camera.snapshot()
	detached.mod_matrix12[0] = 123
	detached.direction_vectors_12[0] = Vector3i.ONE
	assert_eq(camera.snapshot().mod_matrix12, before.mod_matrix12)
	assert_eq(camera.snapshot().direction_vectors_12, before.direction_vectors_12)
	var issue: String = camera.transition_attachment(PackedInt32Array([1, 2, 3]), PackedInt32Array(), false)
	assert_false(issue.is_empty())
	assert_eq(camera.snapshot().mod_matrix12, before.mod_matrix12)
	assert_eq(camera.snapshot().current_ytheta, before.current_ytheta)
	assert_eq(camera.snapshot().destination_ytheta, before.destination_ytheta)

func test_turn_while_attached_updates_controller_vectors() -> void:
	var camera: GameplayCamera = _camera()
	assert_eq(camera.transition_attachment(PackedInt32Array(), QUARTER_TURN, true), "")
	var before: GameplayCameraSnapshot = camera.snapshot()
	assert_eq(camera.request_turn(1), "")
	for index: int in 8:
		var input := GameplayCameraTick.new()
		input.on_entity = true
		input.entity_matrix12 = QUARTER_TURN.duplicate()
		assert_eq(camera.step(input), "", "turn tick %d" % index)
	var after: GameplayCameraSnapshot = camera.snapshot()
	assert_eq(after.twist_counter, 0)
	assert_eq(after.move_timer, 0)
	assert_ne(after.controller_directions, before.controller_directions)
	assert_eq(after.direction_vectors_12.size(), 4)
	for vector: Vector3i in after.direction_vectors_12:
		assert_eq(vector.y, 0)
