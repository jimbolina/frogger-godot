extends RetailTest
## DES2 cactus source setup and the bounded airborne POP against independent facts.

var _data: GameData

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func _joined(values: PackedInt32Array) -> String:
	var texts := PackedStringArray()
	for value: int in values:
		texts.append(str(value))
	return ",".join(texts)

func test_des2_cactus_reaction_setup_matches_independent_facts() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("entity_reactions_retail.tsv")
	rows.pop_front()
	assert_eq(rows.size(), 23)
	var problems := PackedStringArray()
	var map: MapFile = _data.read_map(650, problems)
	assert_not_null(map)
	if map == null:
		return
	assert_eq(map.group_base, Vector3i(-6145, 0, -5377))
	assert_eq(map.group_dimensions, Vector2i(15, 15))
	assert_eq(map.group_size, Vector2i(768, 768))
	var grid_packet: MapPacket = map.packets["GRID"]
	assert_eq(grid_packet.dimensions, Vector2i(42, 44))
	var start_stack: MapGridStack = map.grid_stacks[30 * 42 + 17]
	var target_stack: MapGridStack = map.grid_stacks[30 * 42 + 18]
	assert_eq(map.grid_squares[start_stack.first_square_index + start_stack.square_count - 1].flags, 3)
	assert_eq(map.grid_squares[target_stack.first_square_index + target_stack.square_count - 1].flags, 4097)
	var setup: EntityCollisionSetup = EntityCollisionSetup.from_data(_data, 7)
	assert_eq(setup.error, "")
	if not setup.error.is_empty():
		return
	var by_index: Dictionary[int, int] = {}
	for index: int in setup.definition.entities.size():
		by_index[setup.definition.entities[index].entity_index] = index
	var book: ThemeBook = _data.tables.theme_book()
	for row: PackedStringArray in rows:
		var entity_index: int = int(row[2])
		assert_true(by_index.has(entity_index), "DES2 entity %d" % entity_index)
		if not by_index.has(entity_index):
			continue
		var slot: int = by_index[entity_index]
		var entity: EntityDefinition = setup.definition.entities[slot]
		var contact: FormContactDefinition = setup.definition.contacts[slot]
		var form: MapForm = map.forms[entity.form_grid_id]
		var entry: FormBookEntry = book.get_form(map.general.theme, entity.form_id)
		assert_not_null(entry)
		if entry == null:
			continue
		var writers := PackedInt32Array()
		for source_index: int in map.entities.size():
			if map.entities[source_index].form_grid_id == entity.form_grid_id:
				writers.append(source_index)
		var observed := PackedStringArray([str(contact.resource_id), "DES2.MAP",
			str(entity.entity_index), str(entity.source_offset), str(entity.unique_id),
			str(entity.form_grid_id), str(entity.form_id), entity.form_name,
			str(entity.flags), str(entry.entity_type), str(entry.script_id),
			str(entry.collision_callback), str(entry.bonus_callback),
			str(entry.death_type), str(entry.flags),
			str(_data.model_wad_for(entry, 7, false)),
			str(_data.model_resource_for(entry, 7, false)),
			str(form.source_offset), str(contact.dimensions.x), str(contact.dimensions.y),
			str(contact.offsets.x), str(contact.offsets.y), str(contact.height),
			str(form.stored_max_y), str(contact.max_y), str(contact.radius_squared),
			_joined(contact.grid_flags), _joined(writers)])
		for value: int in entity.matrix12:
			observed.append(str(value))
		assert_eq(contact.unsupported_reason, "", "DES2 entity %d geometry" % entity_index)
		assert_eq(contact.reaction_unsupported_reason, "", "DES2 entity %d reaction" % entity_index)
		assert_eq(observed, row, "DES2 entity %d" % entity_index)
	assert_eq(problems.size(), 0, "\n".join(problems))

func test_des2_airborne_pop_precedes_terrain_landing() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	scenario.entity_reactions = true
	assert_eq(scenario.attach_data(_data, "DES2"), "")
	assert_eq(scenario.initial.spawn_cell, Vector2i(17, 30))
	assert_eq(scenario.initial.spawn_direction, 1)
	var run: TerrainRun = TerrainRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	for tick: int in 5:
		var result: TickResult = run.step(scenario.command_at(tick))
		assert_eq(result.error, "", "DES2 tick %d" % tick)
		if not result.error.is_empty():
			return
		var collision: RunSnapshot = result.collision_snapshot
		assert_not_null(collision)
		if collision == null:
			return
		if tick < 4:
			assert_eq(collision.death_entity_index, -1, "DES2 earlier tick %d" % tick)
			assert_false(collision.entity_hit_indices.has(46), "DES2 earlier cactus %d" % tick)
			for reaction: FormReactionResult in result.entity_contacts:
				assert_ne(reaction.status, FormReactionResult.POP, "DES2 earlier lethal contact %d" % tick)
			continue
		assert_eq(collision.world_position, Vector3i(-683, -1576, 2176))
		assert_eq(collision.death_entity_index, 46)
		assert_eq(collision.death_equate, 23)
		assert_true(collision.flags & 8 != 0)
		assert_eq(collision.mode, 1, "POP remains pending until the next move")
		assert_true(collision.velocity_16 != Vector3i.ZERO, "Airborne jump velocity is preserved")
		var first: FormReactionResult = null
		for reaction: FormReactionResult in result.entity_contacts:
			if reaction.contact != null and reaction.contact.entity_index == 46 and reaction.contact.status == FormContactResult.CONTACT:
				first = reaction
				break
		assert_not_null(first)
		if first != null:
			assert_eq(first.status, FormReactionResult.POP)
			assert_eq(first.contact.local_position, Vector3i(47, -21, 5))
			assert_eq(first.contact.cell, Vector2i.ZERO)
			assert_eq(first.contact.cell_flags, 5)
	var next: TickResult = run.step(scenario.command_at(5))
	assert_eq(next.error, "")
	if next.error.is_empty():
		assert_eq(next.collision_snapshot.mode, 2)
		assert_eq(next.collision_snapshot.death_entity_index, 46)
		assert_eq(next.collision_snapshot.entity_hit_indices.size(), 0)
