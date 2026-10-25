extends RetailTest
## Compares every retail MAP and SkyLand with independent Python facts.

var _data: GameData

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func _digest(values: Variant) -> String:
	var wide := PackedInt64Array()
	for value: int in values:
		wide.append(value)
	return GoldenFiles.list_digest(wide) if not wide.is_empty() else "-"

func _vec(values: PackedInt32Array, vector: Vector3i) -> void:
	values.append_array(PackedInt32Array([vector.x, vector.y, vector.z]))

func _header(animation: MapAnimation) -> PackedInt64Array:
	var b: PackedByteArray = animation.raw_header
	var values := PackedInt64Array([b.decode_s8(0), b.decode_s8(1), b.decode_u16(2), b.decode_u32(4),
		b.decode_u16(8), b.decode_u16(10), b.decode_u32(12), b.decode_u16(16), b.decode_u16(18),
		b.decode_u16(20), b.decode_u16(22), b.decode_u32(24), b.decode_u32(28)])
	return values

func _targets(animation: MapAnimation) -> PackedInt32Array:
	var result := PackedInt32Array()
	var b: PackedByteArray = animation.raw_targets
	for i: int in animation.target_pointers.size():
		result.append(b.decode_u32(i * 12))
		for j: int in 8:
			result.append(b[i * 12 + 4 + j])
	return result

func test_all_map_headers_geometry_groups_lights_and_sections() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("map_facts.tsv")
	var columns: PackedStringArray = rows.pop_front()
	assert_eq(rows.size(), 78)
	var problems := PackedStringArray()
	for row: PackedStringArray in rows:
		var file: MapFile = _data.read_map(int(row[0]), problems)
		assert_not_null(file, row[1])
		if file == null:
			continue
		var vertices := PackedInt32Array()
		for vertex: Vector3i in file.vertices:
			_vec(vertices, vertex)
		var polygons := PackedInt32Array()
		for polygon: MapPolygon in file.polygons:
			polygons.append(polygon.type_index)
			polygons.append_array(polygon.raw_words)
		var groups := PackedInt32Array()
		var visible: Dictionary[int, bool] = {}
		var invisible: Dictionary[int, bool] = {}
		for group: MapGroup in file.groups:
			groups.append_array(group.counts)
			groups.append_array(group.pointers)
			groups.append(group.static_entity_pointer)
			for index: int in group.polygon_indices:
				if group.visible:
					visible[index] = true
				else:
					invisible[index] = true
		var referenced: Dictionary[int, bool] = visible.duplicate()
		referenced.merge(invisible)
		var group_header := PackedInt32Array()
		_vec(group_header, file.group_base)
		group_header.append_array(PackedInt32Array([file.group_dimensions.x, file.group_dimensions.y,
			file.group_size.x, file.group_size.y]))
		var lights := PackedInt64Array()
		for light: MapLight in file.lights:
			lights.append_array(PackedInt64Array([light.category, light.priority, light.parent_id,
				light.light_type, light.color_word]))
			lights.append_array(PackedInt64Array([light.position.x, light.position.y, light.position.z,
				light.direction.x, light.direction.y, light.direction.z]))
			lights.append_array(PackedInt64Array([light.attribute_0, light.attribute_1]))
		var animations := PackedInt64Array()
		var targets := PackedInt32Array()
		var cels := PackedInt32Array()
		for animation: MapAnimation in file.animations:
			animations.append_array(_header(animation))
			targets.append_array(_targets(animation))
			cels.append_array(animation.texture_ids)
		var grid: MapPacket = file.packets["GRID"]
		var values: Array = [int(row[0]), row[1], file.size, file.version, _digest(file.general.raw_words),
			file.vertices.size(), _digest(vertices), file.polygons.size(), _digest(polygons),
			file.group_dimensions.x, file.group_dimensions.y, _digest(group_header), _digest(groups),
			visible.size(), invisible.size(), file.polygons.size() - referenced.size(), file.lights.size(),
			_digest(lights), file.animations.size(), _digest(animations), _digest(targets), _digest(cels),
			grid.dimensions.x, grid.dimensions.y, grid.grid_square_count, file.packets["FORM"].count,
			file.entities.size(), file.packets["ZONE"].count, file.packets["PATH"].count]
		assert_eq(values.size(), row.size(), row[1])
		for i: int in mini(values.size(), row.size()):
			assert_eq(str(values[i]), row[i], "%s %s" % [row[1], columns[i]])
	assert_eq(problems.size(), 0, "\n".join(problems))

func test_all_polygon_type_lists_and_animation_records() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("map_polygons.tsv")
	rows.pop_front()
	var cached_id: int = -1
	var file: MapFile
	const TYPES: Array[String] = ["F3", "F4", "FT3", "FT4", "G3", "G4", "GT3", "GT4", "G2"]
	for row: PackedStringArray in rows:
		if int(row[0]) != cached_id:
			cached_id = int(row[0])
			file = _data.read_map(cached_id)
		if file == null:
			fail_test(row[1])
			continue
		var type_index: int = TYPES.find(row[2])
		var words := PackedInt32Array()
		var count: int = 0
		for polygon: MapPolygon in file.polygons:
			if polygon.type_index == type_index:
				count += 1
				words.append_array(polygon.raw_words)
		assert_eq(str(count), row[3], row[1] + " " + row[2])
		assert_eq(_digest(words), row[4], row[1] + " " + row[2])
	var animation_rows: Array[PackedStringArray] = GoldenFiles.rows("map_animations.tsv")
	animation_rows.pop_front()
	assert_eq(animation_rows.size(), 297)
	for row: PackedStringArray in animation_rows:
		if int(row[0]) != cached_id:
			cached_id = int(row[0])
			file = _data.read_map(cached_id)
		if file == null:
			fail_test(row[1])
			continue
		var animation: MapAnimation = file.animations[int(row[2])]
		var header: PackedInt64Array = _header(animation)
		for i: int in header.size():
			assert_eq(str(header[i]), row[i + 3], "%s animation %s field %d" % [row[1], row[2], i])
		assert_eq(_digest(animation.texture_ids), row[16], row[1])
		assert_eq(_digest(_targets(animation)), row[17], row[1])

func test_both_sky_land_maps() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("sky_land.tsv")
	rows.pop_front()
	assert_eq(rows.size(), 2)
	for row: PackedStringArray in rows:
		var file: SkyLandFile = _data.read_sky_land(row[1].contains("WIN95"))
		assert_not_null(file, row[1])
		if file == null:
			continue
		assert_eq(str(file.dimensions.x), row[2], row[1])
		assert_eq(str(file.dimensions.y), row[3], row[1])
		assert_eq(_digest(file.packed_tiles), row[4], row[1])
		assert_eq(_digest(file.texture_ids), row[5], row[1])
		assert_eq(_digest(file.rotations), row[6], row[1])

func test_independent_animation_counter_samples() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("map_animation_states.tsv")
	rows.pop_front()
	assert_eq(rows.size(), 2970)
	var cached_id: int = -1
	var player := MapAnimationPlayer.new()
	for row: PackedStringArray in rows:
		if int(row[0]) != cached_id:
			cached_id = int(row[0])
			var file: MapFile = _data.read_map(cached_id)
			assert_not_null(file, row[1])
			if file == null:
				continue
			player.configure([], file.animations, _data.remap_for_resource(cached_id), TextureLibrary.new())
		player.seek(int(row[3]) - 1)
		var animation: int = int(row[2])
		var offset: Vector2i = player.track_offset(animation)
		var counters: PackedInt32Array = player.track_counters(animation)
		var values := PackedInt32Array([offset.x, offset.y])
		values.append_array(counters)
		for i: int in values.size():
			assert_eq(str(values[i]), row[i + 4], "%s animation %s tick %s field %d" % [row[1], row[2], row[3], i])

func test_independent_cave_falloff_samples() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("map_lighting.tsv")
	rows.pop_front()
	for row: PackedStringArray in rows:
		var intensity: int = MapLighting.cave_intensity(int(row[2]), int(row[0]), int(row[1]))
		assert_eq(str(intensity), row[4], "cave falloff " + ",".join(row))
