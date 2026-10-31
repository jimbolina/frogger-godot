extends AssetTest
## Compares every committed map and sky-land resource with the independent map
## facts: header values, section counts, the rebuilt polygon and grid records,
## and the vertex, polygon, group, light and animation digests.

const TYPES: Array[String] = ["F3", "F4", "FT3", "FT4", "G3", "G4", "GT3", "GT4", "G2"]

var _maps: Dictionary[int, MapFile] = {}


func _map_path(file_name: String) -> String:
	return "%s/maps/%s.res" % [ASSETS, file_name.get_basename()]


func _map(resource_id: int, file_name: String) -> MapFile:
	if not _maps.has(resource_id):
		var path: String = _map_path(file_name)
		_maps[resource_id] = load(path) as MapFile if ResourceLoader.exists(path) else null
	return _maps[resource_id]


func _digest(values: Variant) -> String:
	var wide := PackedInt64Array()
	for value: int in values:
		wide.append(value)
	return GoldenFiles.list_digest(wide) if not wide.is_empty() else "-"


func _vec(values: PackedInt32Array, vector: Vector3i) -> void:
	values.append_array(PackedInt32Array([vector.x, vector.y, vector.z]))


func _header(animation: MapAnimation) -> PackedInt64Array:
	var b: PackedByteArray = animation.raw_header
	return PackedInt64Array([b.decode_s8(0), b.decode_s8(1), b.decode_u16(2), b.decode_u32(4),
		b.decode_u16(8), b.decode_u16(10), b.decode_u32(12), b.decode_u16(16), b.decode_u16(18),
		b.decode_u16(20), b.decode_u16(22), b.decode_u32(24), b.decode_u32(28)])


func _targets(animation: MapAnimation) -> PackedInt32Array:
	var result := PackedInt32Array()
	var b: PackedByteArray = animation.raw_targets
	for i: int in animation.target_pointers.size():
		result.append(b.decode_u32(i * 12))
		for j: int in 8:
			result.append(b[i * 12 + 4 + j])
	return result


func _fact_values(row: PackedStringArray, file: MapFile) -> Array:
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
			light.light_type, light.color_word, light.position.x, light.position.y, light.position.z,
			light.direction.x, light.direction.y, light.direction.z, light.attribute_0, light.attribute_1]))
	var animations := PackedInt64Array()
	var targets := PackedInt32Array()
	var cels := PackedInt32Array()
	for animation: MapAnimation in file.animations:
		animations.append_array(_header(animation))
		targets.append_array(_targets(animation))
		cels.append_array(animation.texture_ids)
	var grid: MapPacket = file.packets.get("GRID")
	var form: MapPacket = file.packets.get("FORM")
	var zone: MapPacket = file.packets.get("ZONE")
	var path: MapPacket = file.packets.get("PATH")
	return [int(row[0]), row[1], file.size, file.version, _digest(file.general.raw_words),
		file.vertices.size(), _digest(vertices), file.polygons.size(), _digest(polygons),
		file.group_dimensions.x, file.group_dimensions.y, _digest(group_header), _digest(groups),
		visible.size(), invisible.size(), file.polygons.size() - referenced.size(), file.lights.size(),
		_digest(lights), file.animations.size(), _digest(animations), _digest(targets), _digest(cels),
		grid.dimensions.x if grid != null else -1, grid.dimensions.y if grid != null else -1,
		grid.grid_square_count if grid != null else -1, form.count if form != null else -1,
		file.entities.size(), zone.count if zone != null else -1, path.count if path != null else -1]


func test_every_map_resource_matches_the_map_facts() -> void:
	var rows: Array[PackedStringArray] = fact_rows("map_facts.tsv")
	var columns: PackedStringArray = rows.pop_front()
	assert_eq(rows.size(), 78, "map rows")
	var found: int = 0
	for row: PackedStringArray in rows:
		var file: MapFile = _map(int(row[0]), row[1])
		if file == null:
			fail_test("%s has no loadable resource at %s" % [row[1], _map_path(row[1])])
			continue
		found += 1
		var values: Array = _fact_values(row, file)
		assert_eq(values.size(), row.size(), row[1])
		for i: int in mini(values.size(), row.size()):
			assert_eq(str(values[i]), row[i], "%s %s" % [row[1], columns[i]])
	assert_eq(found, 78, "loadable map resources")


func test_rebuilt_sections_match_their_counts() -> void:
	var rows: Array[PackedStringArray] = fact_rows("map_facts.tsv")
	var columns: PackedStringArray = rows.pop_front()
	var at: Dictionary[String, int] = {}
	for i: int in columns.size():
		at[columns[i]] = i
	for row: PackedStringArray in rows:
		var file: MapFile = _map(int(row[0]), row[1])
		if file == null:
			fail_test(row[1])
			continue
		var group_count: int = row[at["groups_x"]].to_int() * row[at["groups_z"]].to_int()
		assert_eq(file.groups.size(), group_count + 1, "%s visible groups and the invisible group" % row[1])
		assert_eq(file.grid_stacks.size(), row[at["grid_x"]].to_int() * row[at["grid_z"]].to_int(), "%s grid stacks" % row[1])
		assert_eq(str(file.grid_squares.size()), row[at["grid_square_count"]], "%s grid squares" % row[1])
		assert_eq(str(file.forms.size()), row[at["form_count"]], "%s forms" % row[1])
		assert_eq(str(file.zones.size()), row[at["zone_count"]], "%s zones" % row[1])
		assert_eq(str(file.paths.size()), row[at["path_count"]], "%s paths" % row[1])


func test_polygon_type_lists_and_animation_records() -> void:
	var rows: Array[PackedStringArray] = fact_rows("map_polygons.tsv")
	rows.pop_front()
	for row: PackedStringArray in rows:
		var file: MapFile = _map(int(row[0]), row[1])
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
	var animation_rows: Array[PackedStringArray] = fact_rows("map_animations.tsv")
	animation_rows.pop_front()
	assert_eq(animation_rows.size(), 297, "animation rows")
	for row: PackedStringArray in animation_rows:
		var file: MapFile = _map(int(row[0]), row[1])
		if file == null or int(row[2]) >= file.animations.size():
			fail_test("%s animation %s" % [row[1], row[2]])
			continue
		var animation: MapAnimation = file.animations[int(row[2])]
		var header: PackedInt64Array = _header(animation)
		for i: int in header.size():
			assert_eq(str(header[i]), row[i + 3], "%s animation %s field %d" % [row[1], row[2], i])
		assert_eq(_digest(animation.texture_ids), row[16], row[1])
		assert_eq(_digest(_targets(animation)), row[17], row[1])


func test_both_sky_land_resources() -> void:
	var rows: Array[PackedStringArray] = fact_rows("sky_land.tsv")
	rows.pop_front()
	assert_eq(rows.size(), 2, "sky-land rows")
	for row: PackedStringArray in rows:
		var path: String = _map_path(row[1])
		var file: SkyLandFile = load(path) as SkyLandFile if ResourceLoader.exists(path) else null
		if file == null:
			fail_test("%s has no loadable resource at %s" % [row[1], path])
			continue
		assert_eq(str(file.dimensions.x), row[2], row[1])
		assert_eq(str(file.dimensions.y), row[3], row[1])
		assert_eq(file.texture_ids.size(), file.dimensions.x * file.dimensions.y, row[1] + " tiles")
		assert_eq(file.rotations.size(), file.texture_ids.size(), row[1] + " rotations")
		assert_eq(_digest(file.packed_tiles), row[4], row[1])
		assert_eq(_digest(file.texture_ids), row[5], row[1])
		assert_eq(_digest(file.rotations), row[6], row[1])


func test_the_catalog_serves_the_committed_maps() -> void:
	var assets: ImportedAssets = catalog()
	assert_true(assets.is_valid(), assets.error)
	if not assets.is_valid():
		return
	var rows: Array[PackedStringArray] = fact_rows("map_facts.tsv")
	rows.pop_front()
	for row: PackedStringArray in rows:
		var problems := PackedStringArray()
		var file: MapFile = assets.read_map(int(row[0]), problems)
		assert_not_null(file, "%s %s" % [row[1], "; ".join(problems)])
		if file != null:
			assert_eq(file.resource_path, _map_path(row[1]), row[1])
	for low_poly: bool in [false, true]:
		var sky: SkyLandFile = assets.read_sky_land(low_poly)
		assert_not_null(sky, "sky land, low poly %s" % low_poly)
		if sky != null:
			assert_eq(sky.resource_path, _map_path("SKY_LAND_WIN95.MAP" if low_poly else "SKY_LAND.MAP"))
