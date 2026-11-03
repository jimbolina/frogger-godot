extends GutTest
## The level support report lists every used item and marks what the port cannot play.

const BUILD: String = "pc-retail-v3.0e"
const ORIGINAL: int = 5
const GENERAL_BANK: int = 500
const ORIGINAL_BANK: int = 501


class SyntheticData extends AssetCatalog:
	var maps: Dictionary[int, MapFile] = {}
	var banks: Dictionary[int, VloFile] = {}
	var codes: PackedStringArray = PackedStringArray()

	func read_map(resource_id: int, problems: PackedStringArray = PackedStringArray()) -> MapFile:
		if not maps.has(resource_id):
			problems.append("no map %d" % resource_id)
			return null
		return maps[resource_id]

	func read_texture_bank(resource_id: int, problems: PackedStringArray = PackedStringArray()) -> VloFile:
		if not banks.has(resource_id):
			problems.append("no bank %d" % resource_id)
			return null
		return banks[resource_id]

	func read_wad(_wad_resource_id: int) -> WadFile:
		return null

	func playable_level_codes() -> PackedStringArray:
		return codes


func test_synthetic_catalog_reports_exact_unmapped_rows() -> void:
	var report: LevelSupportReport = LevelSupportReport.from_catalog(_data())
	assert_eq(report.problems, PackedStringArray())
	var unmapped: Array[LevelSupportReport.Row] = report.unmapped()
	var found := PackedStringArray()
	for row: LevelSupportReport.Row in unmapped:
		found.append("%s|%s|%s" % [row.kind, row.key, ",".join(row.levels)])
		assert_false(row.reason.is_empty(), row.key)
	assert_eq(found, PackedStringArray([
		"callback|0x401000|ORG1",
		"entity|ALIEN_THING|ORG1",
		"remap|txl_org1/2|ORG1",
		"script|SCRIPT_BROKEN|ORG1",
	]))
	if unmapped.size() != 4:
		return
	assert_string_contains(unmapped[0].reason, "collision callback 0x401000 of form TEST_REPOINTED")
	assert_string_contains(unmapped[1].reason, "ALIEN_THING")
	assert_string_contains(unmapped[2].reason, "global texture 999")
	assert_string_contains(unmapped[3].reason, "Unsupported supplied callback name 0 in SCRIPT_BROKEN")
	var unplaced: Array[LevelSupportReport.Row] = report.unplaced()
	assert_eq(unplaced.size(), 1)
	if unplaced.size() != 1:
		return
	assert_eq(unplaced[0].kind, "callback")
	assert_eq(unplaced[0].key, "0x402000")
	assert_eq(unplaced[0].levels, PackedStringArray(["-"]))
	assert_false(unplaced[0].is_mapped())
	assert_true(unplaced[0].reason.begins_with("unplaced: "), unplaced[0].reason)
	assert_string_contains(unplaced[0].reason, "bonus callback 0x402000 of form TEST_UNPLACED")


func test_mapped_rows_are_a_sorted_inventory_with_empty_reasons() -> void:
	var report: LevelSupportReport = LevelSupportReport.from_catalog(_data())
	var keys := PackedStringArray()
	for row: LevelSupportReport.Row in report.rows:
		keys.append(row.kind + "|" + row.key)
	assert_eq(keys, PackedStringArray([
		"callback|0x401000", "callback|0x402000",
		"entity|ALIEN_THING", "entity|MOVING", "entity|STATIC",
		"form|TEST_ALIEN", "form|TEST_FINE_SCRIPT", "form|TEST_MOVING", "form|TEST_REPOINTED", "form|TEST_SCRIPTED",
		"remap|txl_org1/2", "remap|txl_org2",
		"script|SCRIPT_BROKEN", "script|SCRIPT_FINE",
	]))
	for row: LevelSupportReport.Row in report.rows:
		if row.key in ["MOVING", "TEST_MOVING"]:
			assert_eq(row.levels, PackedStringArray(["ORG1", "ORG2"]), row.key)
		if row.key in ["MOVING", "STATIC", "TEST_ALIEN", "TEST_MOVING", "txl_org2", "SCRIPT_FINE"]:
			assert_true(row.is_mapped(), row.key)
			assert_eq(row.reason, "", row.key)
	assert_eq(report.summary(), "2 levels, 14 rows, 4 unmapped, 1 unplaced")
	var lines: PackedStringArray = report.to_tsv_lines()
	assert_eq(lines[0], "# kind\tkey\tlevels\treason")
	assert_eq(lines.size(), 15)
	assert_eq(lines[8], "form\tTEST_MOVING\tORG1,ORG2\t")


func test_named_levels_select_and_unreadable_levels_are_problems() -> void:
	var report: LevelSupportReport = LevelSupportReport.from_catalog(_data(), PackedStringArray(["org2", "ORG3"]))
	assert_eq(report.level_count, 1)
	assert_eq(report.problems.size(), 1)
	assert_string_contains(report.problems[0], "ORG3")
	assert_eq(report.summary(), "1 levels, 6 rows, 0 unmapped, 3 unplaced, 1 problems")
	var unplaced := PackedStringArray()
	for row: LevelSupportReport.Row in report.unplaced():
		unplaced.append(row.kind + "|" + row.key)
	assert_eq(unplaced, PackedStringArray(["callback|0x401000", "callback|0x402000", "entity|ALIEN_THING"]))


func _texts(rows: Array[LevelSupportReport.Row]) -> PackedStringArray:
	var texts := PackedStringArray()
	for row: LevelSupportReport.Row in rows:
		texts.append(row.to_tsv())
	return texts


func _data() -> SyntheticData:
	var data := SyntheticData.new()
	data.version_name = BUILD
	data.codes = PackedStringArray(["ORG1", "ORG2"])
	data.tables = GameTables.new()
	data.tables.theme_book_table = _theme_book()
	data.tables.map_book_table = _map_book()
	data.tables.remap_table = TextureRemapList.new()
	data.tables.remap_table.remaps.append(_remap("txl_org1", 10, PackedInt32Array([100, 101, 999])))
	data.tables.remap_table.remaps.append(_remap("txl_org2", 11, PackedInt32Array([100, 101])))
	data.names = GameNameLists.new()
	data.names.scripts = SyntheticNames.list("SCRIPT_NONE\nSCRIPT_BROKEN\nSCRIPT_FINE\n[CallbackNames]\nSCRIPT_CB_NOT_PORTED\n", false, "Script")
	data.tables.script_table = _scripts(data.names.scripts)
	data.banks[GENERAL_BANK] = _bank(PackedInt32Array([100]))
	data.banks[ORIGINAL_BANK] = _bank(PackedInt32Array([101]))
	var first: MapFile = _map()
	_add_path(first)
	_add_entity(first, 0, _path_info())
	for form_id: int in [1, 2, 3, 4]:
		_add_entity(first, form_id, _matrix())
	var first_polygons: Array[MapPolygon] = [_polygon(0), _polygon(1), _polygon(-1)]
	first.polygons = first_polygons
	var animation := MapAnimation.new()
	animation.texture_ids = PackedInt32Array([2])
	first.animations.append(animation)
	data.maps[10] = first
	var second: MapFile = _map()
	_add_path(second)
	_add_entity(second, 0, _path_info())
	var second_polygons: Array[MapPolygon] = [_polygon(1), _polygon(0)]
	second.polygons = second_polygons
	data.maps[11] = second
	return data


func _theme_book() -> ThemeBook:
	var book := ThemeBook.new()
	for theme: int in FroggerIds.THEMES.size():
		var entry := ThemeBookEntry.new()
		entry.theme = theme
		book.entries.append(entry)
	book.entries[FroggerIds.THEME_GENERAL].high_vlo_id = GENERAL_BANK
	book.entries[ORIGINAL].high_vlo_id = ORIGINAL_BANK
	var spare_general := _form("GEN_SPARE", "STATIC")
	spare_general.theme = FroggerIds.THEME_GENERAL
	book.entries[FroggerIds.THEME_GENERAL].forms.append(spare_general)
	var forms: Array[FormBookEntry] = [
		_form("TEST_MOVING", "MOVING"),
		_form("TEST_REPOINTED", "STATIC"),
		_form("TEST_ALIEN", "ALIEN_THING"),
		_form("TEST_SCRIPTED", "STATIC"),
		_form("TEST_FINE_SCRIPT", "STATIC"),
		_form("TEST_UNPLACED", "STATIC"),
	]
	forms[1].collision_callback = 0x401000
	forms[3].script_id = 1
	forms[4].script_id = 2
	forms[5].bonus_callback = 0x402000
	for local_id: int in forms.size():
		forms[local_id].theme = ORIGINAL
		forms[local_id].local_id = local_id
		book.entries[ORIGINAL].forms.append(forms[local_id])
	return book


func _form(form_name: String, entity_name: String) -> FormBookEntry:
	var form := FormBookEntry.new()
	form.form_name = form_name
	form.entity_name = entity_name
	form.model_id = -1
	return form


func _map_book() -> MapBook:
	var book := MapBook.new()
	for level: int in FroggerIds.LEVEL_CODES.size():
		book.entries.append(MapBookEntry.new())
	var maps: Dictionary[String, int] = {"ORG1": 10, "ORG2": 11}
	for code: String in maps:
		var row: MapBookEntry = book.entries[FroggerIds.level_from_code(code)]
		row.level = FroggerIds.level_from_code(code)
		row.high_map_id = maps[code]
		row.high_remap_pointer = 0x1000 + maps[code]
	return book


func _remap(remap_name: String, resource_id: int, ids: PackedInt32Array) -> TextureRemap:
	var remap := TextureRemap.new()
	remap.name = remap_name
	remap.resource_id = resource_id
	remap.texture_ids = ids
	remap.slots = ids.size()
	return remap


func _scripts(names: NameBank) -> ScriptTable:
	var table := ScriptTable.new()
	for id: int in 3:
		var program := EntityScript.new()
		program.id = id
		program.name = names.name_of(id)
		if id == 1:
			var callback := EntityScript.Command.new()
			callback.opcode = 34
			callback.arguments = PackedInt32Array([0, 0, 0, 0])
			program.commands.append(callback)
		var stop := EntityScript.Command.new()
		stop.opcode = 38
		program.commands.append(stop)
		table.scripts.append(program)
	return table


func _bank(texture_ids: PackedInt32Array) -> VloFile:
	var bank := VloFile.new()
	for texture_id: int in texture_ids:
		var image := VloImage.new()
		image.texture_id = texture_id
		bank.images.append(image)
	return bank


func _polygon(texture_id: int) -> MapPolygon:
	var polygon := MapPolygon.new()
	polygon.texture_id = texture_id
	return polygon


func _map() -> MapFile:
	var map := MapFile.new()
	map.general.theme = ORIGINAL
	for identifier: String in ["EMTP", "PATH"]:
		var packet := MapPacket.new()
		packet.identifier = identifier
		map.packets[identifier] = packet
	return map


func _add_entity(map: MapFile, form_id: int, payload: PackedByteArray) -> void:
	var span := MapEntitySpan.new()
	span.source_offset = 100 + map.entities.size() * 50
	span.end_offset = span.source_offset + 24 + payload.size()
	span.form_id = form_id
	span.unique_id = map.entities.size() + 1
	span.payload = payload
	map.packets["EMTP"].offsets.append(span.source_offset)
	map.packets["EMTP"].count += 1
	map.entities.append(span)


func _matrix() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(32)
	for index: int in 3:
		bytes.encode_s16(index * 8, 4096)
	return bytes


func _path_info() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(12)
	bytes.encode_u16(6, 8)
	bytes.encode_u16(8, 16)
	return bytes


func _add_path(map: MapFile) -> void:
	var path := MapPath.new()
	path.path_index = 0
	path.source_offset = 1000
	var segment := MapPathSegment.new()
	segment.segment_type = 2
	segment.length = 160
	segment.source_offset = 1012
	segment.end = Vector3i(10, 0, 0)
	path.segments.append(segment)
	map.packets["PATH"].offsets.append(path.source_offset)
	map.packets["PATH"].count += 1
	map.paths.append(path)
