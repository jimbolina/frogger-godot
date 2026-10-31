extends RetailTest
## JUN1 high-detail log setup and first SAFE contact against independent retail facts.

var _data: GameData

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func _joined(values: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for value: int in values:
		parts.append(str(value))
	return ",".join(parts)

func test_jun1_log_setup_and_first_safe_contact_match_independent_facts() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("platform_retail.tsv")
	assert_eq(rows.size(), 2)
	if rows.size() != 2:
		return
	var names: PackedStringArray = rows[0]
	var expected: PackedStringArray = rows[1]
	assert_eq(names.size(), expected.size())
	var facts: Dictionary[String, String] = {}
	for index: int in names.size():
		facts[names[index]] = expected[index]
	var map_number: int = int(facts["map_index"])
	var resource: int = int(facts["resource_id"])
	var problems := PackedStringArray()
	var map: MapFile = _data.read_map(resource, problems)
	assert_not_null(map)
	if map == null:
		return
	var setup: EntityCollisionSetup = EntityCollisionSetup.from_data(_data, map_number, false, true)
	assert_eq(setup.error, "")
	if not setup.error.is_empty():
		return
	var slot: int = -1
	for index: int in setup.definition.entities.size():
		if setup.definition.entities[index].entity_index == int(facts["entity_index"]):
			slot = index
			break
	assert_ne(slot, -1)
	if slot < 0:
		return
	var entity: EntityDefinition = setup.definition.entities[slot]
	var contact: FormContactDefinition = setup.definition.contacts[slot]
	var form: MapForm = map.forms[entity.form_grid_id]
	var entry: FormBookEntry = _data.tables.theme_book().get_form(map.general.theme, entity.form_id)
	var path: PathDefinition = entity.path_definition
	var start: PathStart = entity.path_start
	assert_not_null(entry)
	assert_not_null(path)
	assert_not_null(start)
	if entry == null or path == null or start == null:
		return
	var model: MofFile = _data.read_model(_data.model_resource_for(entry, map_number, false), problems)
	assert_not_null(model)
	if model == null:
		return
	var primitive_count: int = 0
	for part: MofPart in model.static_models[0].parts:
		primitive_count += part.collprims.size()
	var segment: PathSegmentDefinition = path.segments[start.segment_index]
	var payload: MapEntityPayload = MapEntityPayload.read_path_info(map.entities[entity.entity_index])
	assert_eq(payload.error, "")
	var grid_setup: TerrainGridSetup = TerrainGridSetup.from_map(map)
	assert_eq(grid_setup.error, "")
	if not grid_setup.error.is_empty():
		return
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	scenario.options.reactions = ScenarioOptions.Reaction.POP
	scenario.options.reactions = ScenarioOptions.Reaction.PLATFORMS
	assert_eq(scenario.attach_data(_data, "JUN1"), "")
	var spawn: Vector2i = scenario.initial.spawn_cell
	var stack: GridStackDefinition = grid_setup.definition.stack_at(spawn)
	assert_not_null(stack)
	if stack == null or stack.square_count == 0:
		return
	var spawn_square: GridSquareDefinition = grid_setup.definition.squares[stack.first_square_index + stack.square_count - 1]
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var initial_pose: EntitySnapshot = run.snapshot().entities.entities[slot]
	assert_not_null(initial_pose.path)
	if initial_pose.path == null:
		return
	var accepted: TickResult = null
	var command_tick: int = -1
	var accepted_contact: FormReactionResult = null
	for tick: int in 10:
		var result: TickResult = run.step(scenario.command_at(tick))
		assert_eq(result.error, "", "JUN1 command %d" % tick)
		if not result.error.is_empty():
			return
		for reaction: FormReactionResult in result.entity_contacts:
			if reaction.status == FormReactionResult.SAFE and reaction.contact.entity_index == entity.entity_index:
				accepted = result
				accepted_contact = reaction
				command_tick = tick
				break
		if accepted != null:
			break
	assert_not_null(accepted)
	if accepted == null:
		return
	var pose: EntitySnapshot = accepted.move_snapshot.entities.entities[slot]
	var frog: Vector3i = accepted.move_snapshot.frog.world_position
	var hit: FormContactResult = accepted_contact.contact
	assert_eq(hit.status, FormContactResult.CONTACT)
	assert_eq(accepted.collision_snapshot.attachment.current_entity_index, entity.entity_index)
	var delta: Vector3i = frog - Vector3i(pose.matrix12[9], pose.matrix12[10], pose.matrix12[11])
	var observed: Dictionary[String, String] = {
		"resource_id": str(entity.resource_id), "map": "JUN1.MAP", "map_index": str(map_number),
		"entity_index": str(entity.entity_index), "source_offset": str(entity.source_offset),
		"unique_id": str(entity.unique_id), "form_grid_id": str(entity.form_grid_id),
		"form_id": str(entity.form_id), "form_name": entity.form_name,
		"entity_name": entity.entity_name, "entity_flags": str(entity.flags),
		"entity_type": str(entry.entity_type), "script_id": str(entity.script_id),
		"collision_callback": str(entity.collision_callback), "bonus_callback": str(entity.bonus_callback),
		"book_flags": str(contact.form_book_flags), "wad_id": str(_data.model_wad_for(entry, map_number, false)),
		"model_resource_id": str(_data.model_resource_for(entry, map_number, false)),
		"model_kind": MofFile.KIND_NAMES[model.kind], "primitive_count": str(primitive_count),
		"form_source_offset": str(form.source_offset), "xnum": str(contact.dimensions.x),
		"znum": str(contact.dimensions.y), "xofs": str(contact.offsets.x), "zofs": str(contact.offsets.y),
		"height": str(contact.height), "stored_max_y": str(form.stored_max_y),
		"runtime_max_y": str(contact.max_y), "radius_squared": str(contact.radius_squared),
		"grid_flags": _joined(contact.grid_flags), "path_index": str(path.path_index),
		"segment_index": str(start.segment_index), "segment_distance": str(start.distance),
		"motion_flags": str(payload.motion_flags), "speed": str(start.speed),
		"path_padding": str(map.entities[entity.entity_index].payload.decode_u16(10)),
		"segment_type": str(segment.segment_type), "segment_length": str(segment.length),
		"line_start_x": str(segment.start.x), "line_start_y": str(segment.start.y), "line_start_z": str(segment.start.z),
		"line_end_x": str(segment.end.x), "line_end_y": str(segment.end.y), "line_end_z": str(segment.end.z),
		"initial_x": str(initial_pose.path.position.x), "initial_y": str(initial_pose.path.position.y), "initial_z": str(initial_pose.path.position.z),
		"initial_tangent_x": str(initial_pose.path.tangent.x), "initial_tangent_y": str(initial_pose.path.tangent.y), "initial_tangent_z": str(initial_pose.path.tangent.z),
		"spawn_x": str(spawn.x), "spawn_z": str(spawn.y),
		"spawn_direction": str(scenario.initial.spawn_direction), "spawn_y": str(GridQueries.square_centre(grid_setup.definition, spawn_square).y),
		"command_tick": str(command_tick), "entity_tick": str(accepted.move_snapshot.entities.tick_index),
		"frog_x": str(frog.x), "frog_y": str(frog.y), "frog_z": str(frog.z),
		"entity_x": str(pose.matrix12[9]), "entity_y": str(pose.matrix12[10]), "entity_z": str(pose.matrix12[11]),
		"local_x": str(hit.local_position.x), "local_y": str(hit.local_position.y), "local_z": str(hit.local_position.z),
		"cell_x": str(hit.cell.x), "cell_z": str(hit.cell.y), "contact_flags": str(hit.cell_flags),
		"distance_squared": str(delta.length_squared()),
	}
	for index: int in 12:
		observed["initial_matrix_%d" % index] = str(initial_pose.matrix12[index])
	for name: String in names:
		assert_true(observed.has(name), "Unverified retail platform field %s" % name)
		if observed.has(name):
			assert_eq(observed[name], facts[name], "JUN1 %s" % name)
	assert_eq(problems.size(), 0, "\n".join(problems))
