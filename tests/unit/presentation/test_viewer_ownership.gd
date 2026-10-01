extends GutTest
## Real synthetic archive handles exercise every viewer's borrowed/owned lifetime contract.

const SCENES: PackedStringArray = ["res://scenes/tools/texture_viewer.tscn", "res://scenes/tools/model_viewer.tscn", "res://scenes/tools/map_viewer.tscn"]
const PAYLOAD: String = "viewer lifetime!"
var _opened: Array[GameData] = []
var _folders := PackedStringArray()


func after_each() -> void:
	for data: GameData in _opened:
		data.close()
	_opened.clear()
	for folder: String in _folders:
		DirAccess.remove_absolute(folder.path_join("FROGGER.EXE"))
		DirAccess.remove_absolute(folder.path_join("FROGPSX.MWD"))
		DirAccess.remove_absolute(folder)
	_folders.clear()


func _data() -> GameData:
	var folder: String = "user://viewer_ownership_%d" % _folders.size()
	_folders.append(folder)
	assert_eq(DirAccess.make_dir_recursive_absolute(folder), OK)
	var fake := SyntheticExe.new()
	fake.add_mwi(0x100, [["PAYLOAD.BIN", 0, MwiEntry.FLAG_SINGLE_ACCESS]])
	var file: FileAccess = FileAccess.open(folder.path_join("FROGGER.EXE"), FileAccess.WRITE)
	file.store_buffer(fake.bytes)
	file.close()
	var archive_bytes := PackedByteArray()
	archive_bytes.resize(MwiEntry.SECTOR_SIZE)
	for i: int in 4:
		archive_bytes[i] = MwdArchive.SIGNATURE.to_ascii_buffer()[i]
	archive_bytes.append_array(PAYLOAD.to_ascii_buffer())
	file = FileAccess.open(folder.path_join("FROGPSX.MWD"), FileAccess.WRITE)
	file.store_buffer(archive_bytes)
	file.close()
	var data: GameData = GameData.open(RetailDirSource.new(folder), fake.version)
	assert_true(data.is_valid(), data.error)
	_opened.append(data)
	return data


func _viewer(path: String) -> Node:
	var scene: PackedScene = load(path)
	var viewer: Node = scene.instantiate()
	viewer.set("auto_open", false)
	add_child(viewer)
	return viewer


func _assert_readable(data: GameData, context: String) -> void:
	assert_not_null(data.archive._file, context)
	if data.archive._file != null:
		assert_eq(data.read_resource(0).get_string_from_ascii(), PAYLOAD, context)


func test_freeing_borrowed_viewers_keeps_shared_archive_usable() -> void:
	for path: String in SCENES:
		var data: GameData = _data()
		var first: Node = _viewer(path)
		var second: Node = _viewer("res://scenes/tools/texture_viewer.tscn")
		first.call("open_data", data)
		first.call("open_data", data)
		second.call("open_data", data)
		first.free()
		_assert_readable(data, path + " borrowed source remains usable by another viewer")
		var second_data: GameData = second.get("data")
		assert_same(second_data, data)
		second.free()
		_assert_readable(data, path + " caller still owns the source")


func test_independent_owned_viewers_close_only_their_own_archive() -> void:
	for path: String in SCENES:
		var first_data: GameData = _data()
		var second_data: GameData = _data()
		var first: Node = _viewer(path)
		var second: Node = _viewer(path)
		first.call("open_data", first_data, true)
		second.call("open_data", second_data, true)
		first.free()
		assert_null(first_data.archive._file, path + " owned source closes on exit")
		_assert_readable(second_data, path + " independent source remains open")
		second.free()
		assert_null(second_data.archive._file)


func test_replacement_closes_owned_data_and_preserves_borrowed_data() -> void:
	for path: String in SCENES:
		var owned: GameData = _data()
		var borrowed: GameData = _data()
		var replacement: GameData = _data()
		var viewer: Node = _viewer(path)
		viewer.call("open_data", owned, true)
		viewer.call("open_data", borrowed)
		assert_null(owned.archive._file, path + " replacement closes owned source")
		viewer.call("open_data", replacement, true)
		_assert_readable(borrowed, path + " replacement preserves borrowed source")
		viewer.call("open_data", null)
		assert_null(replacement.archive._file, path + " null replacement closes owned source")
		viewer.free()


func test_same_object_retains_ownership_and_can_be_explicitly_adopted() -> void:
	for path: String in SCENES:
		var owned: GameData = _data()
		var viewer: Node = _viewer(path)
		viewer.call("open_data", owned, true)
		viewer.call("open_data", owned)
		_assert_readable(owned, path + " same object was not closed")
		viewer.free()
		assert_null(owned.archive._file, path + " same object retains ownership")
		var adopted: GameData = _data()
		viewer = _viewer(path)
		viewer.call("open_data", adopted)
		viewer.call("open_data", adopted, true)
		_assert_readable(adopted, path + " explicit adoption does not close data")
		viewer.free()
		assert_null(adopted.archive._file)


func test_invalid_replacement_preserves_borrowed_archive_and_closes_owned_archive() -> void:
	for path: String in SCENES:
		var borrowed: GameData = _data()
		var invalid: GameData = _data()
		invalid.error = "Invalid synthetic source"
		var viewer: Node = _viewer(path)
		viewer.call("open_data", borrowed)
		viewer.call("open_data", invalid, true)
		_assert_readable(borrowed, path)
		viewer.free()
		assert_null(invalid.archive._file, path + " invalid owned source closes")


func test_detaching_live_viewers_releases_owned_data_but_preserves_borrowed_archive() -> void:
	for path: String in SCENES:
		var borrowed: GameData = _data()
		var owned: GameData = _data()
		var first: Node = _viewer(path)
		var second: Node = _viewer(path)
		first.call("open_data", borrowed)
		second.call("open_data", owned, true)
		remove_child(first)
		remove_child(second)
		await get_tree().process_frame
		var first_data: GameData = first.get("data")
		var second_data: GameData = second.get("data")
		assert_null(first_data)
		assert_null(second_data)
		_assert_readable(borrowed, path + " detached viewer released borrowed reference")
		assert_null(owned.archive._file, path + " detached owned viewer closes source")
		first.free()
		second.free()
