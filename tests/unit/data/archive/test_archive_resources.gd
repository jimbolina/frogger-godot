extends GutTest
## MwiIndex and WadFile survive a resource save and load, rebuilding their lookups.

const ROOT: String = "user://test_archive_resources"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)


func after_all() -> void:
	for file: String in DirAccess.get_files_at(ROOT):
		DirAccess.remove_absolute(ROOT.path_join(file))
	DirAccess.remove_absolute(ROOT)


func _round_trip(resource: Resource, file_name: String) -> Resource:
	var path: String = ROOT.path_join(file_name)
	assert_eq(ResourceSaver.save(resource, path), OK, file_name)
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)


func _entry(index: int, path: String, name_offset: int) -> MwiEntry:
	var entry := MwiEntry.new()
	entry.index = index
	entry.path = path
	entry.name_offset = name_offset
	entry.flags = MwiEntry.FLAG_SINGLE_ACCESS | MwiEntry.FLAG_AUTOMATIC_COMPRESSION
	entry.type_id = 2
	entry.sector_offset = 9
	entry.packed_size = 40
	entry.unpacked_size = 64
	entry.safety_margin_words = 3
	return entry


func test_index_round_trip_rebuilds_name_lookup() -> void:
	var index := MwiIndex.new()
	index.entries.append(_entry(0, "PACKED\\FIXE_VRAM.VLO", 64))
	index.entries.append(_entry(1, "", MwiEntry.NO_NAME))
	index.entries.append(_entry(2, "MAPS\\fixe_vram.vlo", 90))
	var loaded := _round_trip(index, "index.tres") as MwiIndex
	assert_not_null(loaded)
	assert_eq(loaded.size(), 3)
	assert_eq(loaded.find_by_name("fixe_vram.vlo"), loaded.entries[0], "the first matching name wins")
	assert_null(loaded.find_by_name("file 1"), "unnamed entries are not looked up by name")
	var entry: MwiEntry = loaded.entries[0]
	assert_eq([entry.path, entry.flags, entry.type_id, entry.sector_offset, entry.packed_size,
		entry.unpacked_size, entry.safety_margin_words, entry.name_offset],
		["PACKED\\FIXE_VRAM.VLO", 17, 2, 9, 40, 64, 3, 64])
	assert_eq(loaded.entries[1].name_offset, MwiEntry.NO_NAME)


func test_wad_round_trip_and_child_alias() -> void:
	var wad := WadFile.new()
	var child: WadFile.Child = WadFile.Child.new()
	child.resource_id = 5
	child.type_id = 4
	child.data = "abc".to_ascii_buffer()
	wad.children.append(child)
	var typed: Array[WadFile.Child] = wad.children
	assert_eq(typed.size(), 1)
	var loaded := _round_trip(wad, "wad.tres") as WadFile
	assert_not_null(loaded)
	assert_true(loaded.children[0] is WadChild)
	assert_eq(loaded.children[0].resource_id, 5)
	assert_eq(loaded.child_contents(loaded.children[0]), "abc".to_ascii_buffer())
