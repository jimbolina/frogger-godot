extends GutTest
## Asset-free live creation, retirement, source identity and detached ownership.

func _lifecycle() -> EntityLifecycleDefinition:
	var result := EntityLifecycleDefinition.new()
	result.group_base = Vector3i(-4096, 0, -4096)
	result.group_dimensions = Vector2i.ONE
	result.group_size = Vector2i(8192, 8192)
	result.polygon_counts = PackedInt32Array([0])
	return result

func _camera(x: int = 0) -> GameplayCameraSnapshot:
	var result := GameplayCameraSnapshot.new()
	result.source_world = Vector3i(x, -500, -500)
	result.target_world = Vector3i(x, 0, 0)
	result.axis_x_12 = Vector3i(4096, 0, 0)
	result.axis_y_12 = Vector3i(0, 2896, -2896)
	result.axis_z_12 = Vector3i(0, 2896, 2896)
	return result

func _static(index: int, flags: int = 0, script_id: int = 0) -> EntityDefinition:
	var result := EntityDefinition.new()
	result.entity_name = "STATIC"
	result.entity_index = index
	result.unique_id = 8
	result.flags = flags
	result.script_id = script_id
	return result

func _moving(index: int) -> EntityDefinition:
	var result := _static(index)
	result.entity_name = "MOVING"
	result.flags = EntityDefinition.ALIGN_TO_WORLD
	var path := PathDefinition.new()
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 100
	segment.start = Vector3i.ZERO
	segment.end = Vector3i(100, 0, 0)
	path.segments.append(segment)
	result.path_definition = path
	result.path_start = PathStart.new()
	result.path_start.speed = 10
	return result

func test_dormant_creation_next_tick_and_detached_source_identities() -> void:
	var definitions: Array[EntityDefinition] = [_static(2), _moving(5), _static(9, EntityDefinition.NO_DISPLAY), _static(12, 0, 4)]
	var run: EntityRun = EntityRun.create(definitions, _lifecycle())
	assert_eq(run.error, "")
	var zero: EntityRunSnapshot = run.snapshot()
	assert_true(zero.lifecycle_enabled)
	assert_eq(zero.entities.size(), 4)
	assert_eq(zero.live_order, PackedInt32Array())
	assert_false(zero.entities[0].live)
	assert_false(zero.entities[3].lifecycle_supported)
	assert_eq(run.step(0), "")
	assert_eq(run.snapshot().entities[1].path.position, Vector3i(10, 0, 0))
	assert_eq(run.snapshot().live_order, PackedInt32Array())
	assert_eq(run.apply_visibility(_camera()), "")
	var created: EntityRunSnapshot = run.snapshot()
	assert_eq(created.live_order, PackedInt32Array([2, 9, 5]))
	assert_eq(created.lifecycle_events, ["create:5:1", "create:9:1", "create:2:1"])
	assert_true(created.entities[2].live)
	assert_false(created.entities[3].live)
	created.entities[0].live = false
	created.live_order.clear()
	created.selected_groups.clear()
	created.lifecycle_events.clear()
	assert_true(run.snapshot().entities[0].live)
	assert_eq(run.snapshot().live_order, PackedInt32Array([2, 9, 5]))
	assert_eq(run.step(1), "")
	assert_eq(run.snapshot().entities[1].path.position, Vector3i(20, 0, 0))
	assert_true(run.snapshot().entities[0].destroy_pending)
	assert_eq(run.snapshot().lifecycle_events.size(), 0)
	assert_eq(run.apply_visibility(_camera()), "")
	assert_false(run.snapshot().entities[0].destroy_pending)
	assert_eq(run.snapshot().entities[0].generation, 1)

func test_offscreen_destroy_attachment_pin_and_recreation() -> void:
	var run: EntityRun = EntityRun.create([_static(4), _moving(7)], _lifecycle())
	assert_eq(run.error, "")
	assert_eq(run.apply_visibility(_camera()), "")
	assert_eq(run.snapshot().live_order, PackedInt32Array([4, 7]))
	assert_eq(run.step(0), "")
	assert_eq(run.apply_visibility(_camera(100000)), "")
	assert_eq(run.snapshot().selected_groups, PackedInt32Array())
	assert_true(run.snapshot().entities[0].destroy_pending)
	assert_eq(run.step(1, 4), "")
	assert_true(run.snapshot().entities[0].live)
	assert_false(run.snapshot().entities[1].live)
	assert_eq(run.snapshot().lifecycle_events, ["destroy:7:1"])
	assert_eq(run.snapshot().entities[1].path.position, Vector3i(20, 0, 0))
	assert_eq(run.apply_visibility(_camera(100000)), "")
	assert_eq(run.step(2), "")
	assert_false(run.snapshot().entities[0].live)
	assert_eq(run.snapshot().lifecycle_events, ["destroy:4:1"])
	assert_eq(run.apply_visibility(_camera()), "")
	assert_eq(run.snapshot().live_order, PackedInt32Array([4, 7]))
	assert_eq(run.snapshot().entities[0].generation, 2)
	assert_eq(run.snapshot().entities[1].generation, 2)

func test_invalid_visibility_reset_and_copy_preserve_committed_lifecycle() -> void:
	var geometry: EntityLifecycleDefinition = _lifecycle()
	var run: EntityRun = EntityRun.create([_static(3)], geometry)
	assert_eq(run.error, "")
	geometry.polygon_counts[0] = 2500
	assert_eq(run.apply_visibility(_camera()), "")
	var before: EntityRunSnapshot = run.snapshot()
	var broken_camera: GameplayCameraSnapshot = _camera()
	broken_camera.axis_z_12 = Vector3i.ZERO
	assert_false(run.apply_visibility(broken_camera).is_empty())
	assert_eq(run.snapshot().live_order, before.live_order)
	assert_eq(run.snapshot().lifecycle_events, before.lifecycle_events)
	assert_false(run.step(1).is_empty())
	assert_eq(run.snapshot().tick_index, before.tick_index)
	var copy: EntityRun = run.copy()
	assert_eq(copy.step(0), "")
	assert_eq(run.snapshot().tick_index, 0)
	assert_eq(run.reset(), "")
	assert_eq(run.snapshot().live_order, PackedInt32Array())
	assert_eq(run.snapshot().entities[0].generation, 0)

func test_hidden_static_and_invalid_attachment_do_not_create_or_advance() -> void:
	var hidden: EntityDefinition = _static(2, EntityDefinition.HIDDEN)
	var supported: EntityDefinition = _moving(5)
	var run: EntityRun = EntityRun.create([hidden, supported], _lifecycle())
	assert_eq(run.error, "")
	assert_false(run.step(0, 5).is_empty())
	assert_eq(run.snapshot().tick_index, 0)
	assert_eq(run.snapshot().entities[1].path.position, Vector3i.ZERO)
	assert_eq(run.apply_visibility(_camera()), "")
	assert_false(run.snapshot().entities[0].live)
	assert_eq(run.snapshot().live_order, PackedInt32Array([5]))
	assert_false(run.step(0, 2).is_empty())
	assert_eq(run.snapshot().tick_index, 0)
	assert_eq(run.step(0, 5), "")
	assert_eq(run.snapshot().entities[1].path.position, Vector3i(10, 0, 0))

func test_hidden_no_collision_no_movement_and_two_list_orders() -> void:
	var paused: EntityDefinition = _moving(9)
	paused.flags |= EntityDefinition.NO_MOVEMENT
	var definitions: Array[EntityDefinition] = [
		_static(2, EntityDefinition.HIDDEN),
		_static(4, EntityDefinition.NO_COLLISION),
		_moving(7),
		paused,
		_static(12),
	]
	definitions[2].flags |= EntityDefinition.HIDDEN
	var collision := EntityCollisionDefinition.new()
	collision.entities.assign(definitions)
	collision.group_base = _lifecycle().group_base
	collision.group_dimensions = _lifecycle().group_dimensions
	collision.group_size = _lifecycle().group_size
	collision.lifecycle = _lifecycle()
	for definition: EntityDefinition in definitions:
		var contact := FormContactDefinition.new()
		contact.entity_index = definition.entity_index
		contact.unique_id = definition.unique_id
		contact.form_grid_id = definition.form_grid_id
		contact.form_id = definition.form_id
		contact.form_name = definition.form_name
		contact.entity_flags = definition.flags
		collision.contacts.append(contact)
	assert_eq(collision.validate(), "")
	var run: EntityRun = EntityRun.create(definitions, collision.lifecycle)
	assert_eq(run.error, "")
	assert_eq(run.apply_visibility(_camera()), "")
	var snapshot: EntityRunSnapshot = run.snapshot()
	assert_false(snapshot.entities[0].live)
	assert_true(snapshot.entities[1].live)
	assert_false(snapshot.entities[2].live)
	assert_true(snapshot.entities[3].live)
	assert_eq(snapshot.live_order, PackedInt32Array([4, 12, 9]))
	assert_eq(EntityContactOrder.indices(collision, snapshot, Vector3i.ZERO), PackedInt32Array([9, 12, 4]))
	assert_eq(run.step(0), "")
	assert_eq(run.snapshot().entities[2].path.position, Vector3i(10, 0, 0))
	assert_eq(run.snapshot().entities[3].path.position, Vector3i.ZERO)
	assert_false(bool(run.snapshot().entities[3].path.flags & PathStart.ACTIVE))

func test_destroy_and_recreate_share_tick_in_source_event_order() -> void:
	var run: EntityRun = EntityRun.create([_static(5)], _lifecycle())
	assert_eq(run.error, "")
	assert_eq(run.apply_visibility(_camera()), "")
	assert_eq(run.step(0), "")
	assert_true(run.snapshot().entities[0].destroy_pending)
	assert_eq(run.step(1), "")
	assert_false(run.snapshot().entities[0].live)
	assert_eq(run.snapshot().lifecycle_events, ["destroy:5:1"])
	assert_eq(run.apply_visibility(_camera()), "")
	assert_eq(run.snapshot().lifecycle_events, ["destroy:5:1", "create:5:2"])
	assert_eq(run.snapshot().live_order, PackedInt32Array([5]))
