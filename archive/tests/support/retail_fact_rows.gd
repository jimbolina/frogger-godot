class_name RetailFactRows
extends RefCounted
## Builds rows of the retail golden schemas from decoded records, so every
## archive test that compares with [code]exe_forms.tsv[/code],
## [code]exe_scripts.tsv[/code], [code]exe_remaps.tsv[/code],
## [code]demos.tsv[/code] or [code]entities_retail.tsv[/code] writes the same
## columns (see [code]tests/golden/specs/executable-tables.md[/code],
## [code]demos.md[/code] and [code]entities.md[/code]).


## The [code]exe_forms.tsv[/code] row of [param form].
static func form_row(form: FormBookEntry) -> PackedStringArray:
	return PackedStringArray([FroggerIds.theme_name(form.theme), str(form.local_id), str(form.global_id), form.form_name,
		str(form.entity_type), form.entity_name, str(form.model_id), str(form.script_id), str(form.flags),
		GoldenFiles.hex(form.collision_callback), str(form.radius_squared), str(form.death_type), form.death_type_name(),
		GoldenFiles.hex(form.bonus_callback)])


## The [code]exe_remaps.tsv[/code] row of [param remap], the remap at [param position] of the remap list.
static func remap_row(position: int, remap: TextureRemap) -> PackedStringArray:
	return PackedStringArray([str(position), remap.name, GoldenFiles.hex(remap.file_offset), str(remap.resource_id),
		str(remap.size()), GoldenFiles.list_digest32(remap.texture_ids), str(remap.global_id(0)) if remap.size() > 0 else "",
		str(remap.global_id(remap.size() - 1)) if remap.size() > 0 else ""])


## The [code]exe_scripts.tsv[/code] row of [param script].
static func script_row(script: EntityScript) -> PackedStringArray:
	var words: PackedInt32Array = script.words()
	return PackedStringArray([str(script.id), script.name, GoldenFiles.hex(script.pointer), str(script.commands.size()),
		str(words.size()), GoldenFiles.list_digest32(words),
		script.commands[0].name() if not script.is_empty() else "", script.commands[-1].name() if not script.is_empty() else ""])


## The [code]demos.tsv[/code] rows of [param catalog]'s demo table: the
## low-detail list, then the high-detail list, skipped rows left out. With
## [param resources] only rows naming one of those resource ids are built.
## Demos that cannot be read are described in [param problems].
static func demo_rows(catalog: AssetCatalog, problems: PackedStringArray, resources: PackedInt64Array = PackedInt64Array()) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for low: bool in [true, false]:
		for entry: DemoTableEntry in catalog.tables.demo_table().entries:
			if entry.is_skipped():
				continue
			var resource_id: int = entry.demo_id(low)
			if not resources.is_empty() and not resources.has(resource_id):
				continue
			var demo: SourceDemoFile = catalog.read_demo(resource_id, problems)
			if demo == null:
				problems.append("demo resource %d does not read" % resource_id)
				continue
			rows.append(demo_row(low, entry.level, resource_id, demo))
	return rows


## The [code]demos.tsv[/code] row of [param demo], resource [param resource_id]
## of [param level] in the low-detail list when [param low].
static func demo_row(low: bool, level: int, resource_id: int, demo: SourceDemoFile) -> PackedStringArray:
	var values := PackedInt64Array()
	var counts := PackedInt32Array()
	counts.resize(10)
	for byte: int in demo.input_bytes:
		values.append(byte)
		if byte & 128:
			counts[0] += 1
		else:
			counts[1 + (byte & 3)] += 1
		for bit: int in range(2, 7):
			if byte & (1 << bit):
				counts[3 + bit] += 1
	var row := PackedStringArray(["low" if low else "high", str(level), str(resource_id), str(demo.duration),
		str(demo.start_grid_x), str(demo.start_grid_z), str(values.size()), GoldenFiles.list_digest(values)])
	for count: int in counts:
		row.append(str(count))
	return row


## The [code]entities_retail.tsv[/code] row of map [param resource_id] of
## [param catalog]: identities, generic STATIC and MOVING base records and
## the entities generic setup accepts. Returns an empty row, and describes
## every failure in [param problems], when the map cannot be decoded.
static func entity_row(catalog: AssetCatalog, resource_id: int, problems: PackedStringArray) -> PackedStringArray:
	var entry: MwiEntry = catalog.mwi.get_entry(resource_id)
	var map_name: String = entry.display_name() if entry != null else str(resource_id)
	var file: MapFile = catalog.read_map(resource_id, problems)
	if file == null:
		problems.append("%s does not decode" % map_name)
		return PackedStringArray()
	var book: ThemeBook = catalog.tables.theme_book()
	var identity := PackedInt64Array()
	var records := PackedInt64Array()
	var static_count: int = 0
	var moving_count: int = 0
	for index: int in file.entities.size():
		var span: MapEntitySpan = file.entities[index]
		var form: FormBookEntry = book.get_form(file.general.theme, span.form_id)
		identity.append_array(PackedInt64Array([index, span.source_offset, span.end_offset,
			span.form_grid_id, span.unique_id, span.form_id, span.flags,
			form.entity_type if form != null else -1,
			form.script_id if form != null else -1,
			form.collision_callback if form != null else -1,
			form.bonus_callback if form != null else -1]))
		if form == null:
			continue
		if form.entity_name == "STATIC":
			var matrix: MapEntityPayload = MapEntityPayload.read_matrix(span)
			if not matrix.error.is_empty():
				problems.append("%s entity %d: %s" % [map_name, index, matrix.error])
			else:
				records.append_array(PackedInt64Array([index, 0]))
				for value: int in matrix.matrix12:
					records.append(value)
			static_count += 1
		elif form.entity_name == "MOVING":
			var info: MapEntityPayload = MapEntityPayload.read_path_info(span)
			records.append_array(PackedInt64Array([index, 1, info.path_index,
				info.segment_index, info.segment_distance, info.motion_flags, info.speed]))
			moving_count += 1
	var setup: EntitySetup = EntitySetup.from_map(file, book, map_name, resource_id, catalog.version_name)
	if not setup.error.is_empty():
		problems.append("%s entity setup: %s" % [map_name, setup.error])
	var accepted := PackedInt64Array()
	for definition: EntityDefinition in setup.definitions:
		accepted.append_array(PackedInt64Array([definition.entity_index, definition.unique_id]))
	return PackedStringArray([str(resource_id), map_name, str(file.entities.size()),
		str(static_count), str(moving_count), str(setup.definitions.size()),
		_digest(identity), _digest(records), _digest(accepted)])


static func _digest(values: PackedInt64Array) -> String:
	return GoldenFiles.list_digest(values) if not values.is_empty() else "-"
