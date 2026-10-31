extends GutTest
## MwiIndex, WadFile and MwdArchive on small hand-built files.

const ROOT: String = "user://test_containers"


## Little-endian helper for building test buffers.
static func u32s(values: Array[int]) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(values.size() * 4)
	for i: int in values.size():
		out.encode_u32(i * 4, values[i] & 0xFFFFFFFF)
	return out


## One 32-byte MWI record.
static func mwi_record(name_offset: int, flags: int, type_id: int, sector: int, packed: int, unpacked: int, margin: int = 0) -> PackedByteArray:
	return u32s([name_offset, flags, type_id, sector, 0, 0, packed, unpacked | (margin << 24)])


## An MWI of [param records] followed by [param names] (each NUL-terminated and
## 4-byte aligned, in order); record name offsets are filled in automatically.
static func build_mwi(records: Array[Array], names: Array[String]) -> PackedByteArray:
	var table_size: int = records.size() * MwiEntry.ENTRY_SIZE
	var name_blob := PackedByteArray()
	var name_offsets: Array[int] = []
	for n: String in names:
		name_offsets.append(table_size + name_blob.size())
		name_blob.append_array(n.to_ascii_buffer())
		name_blob.append(0)
		while name_blob.size() % 4 != 0:
			name_blob.append(0)
	var out := PackedByteArray()
	for i: int in records.size():
		var r: Array = records[i]
		var name_offset: int = name_offsets[i] if i < names.size() else MwiEntry.NO_NAME
		var flags: int = r[0]
		var type_id: int = r[1]
		var sector: int = r[2]
		var packed: int = r[3]
		var unpacked: int = r[4]
		out.append_array(mwi_record(name_offset, flags, type_id, sector, packed, unpacked))
	out.append_array(name_blob)
	return out


## A WAD holding [param files] as [resource id, type id, bytes] triples.
static func build_wad(files: Array[Array]) -> PackedByteArray:
	var out := PackedByteArray()
	for f: Array in files:
		var data: PackedByteArray = f[2]
		out.append_array(u32s([f[0], f[1], data.size(), 0]))
		out.append_array(data)
		while out.size() % 4 != 0:
			out.append(0)
	out.append_array(u32s([-1, 0, 0, 0]))
	return out


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)


func after_all() -> void:
	for file: String in DirAccess.get_files_at(ROOT):
		DirAccess.remove_absolute(ROOT.path_join(file))
	DirAccess.remove_absolute(ROOT)


func test_mwi_entries_names_and_flags() -> void:
	var bytes: PackedByteArray = build_mwi([
		[MwiEntry.FLAG_SINGLE_ACCESS | MwiEntry.FLAG_AUTOMATIC_COMPRESSION, 1, 1, 100, 400],
		[MwiEntry.FLAG_IS_GROUP | MwiEntry.FLAG_AUTOMATIC_COMPRESSION, -1, 2, 50, 90],
		[MwiEntry.FLAG_GROUP_ACCESS, 4, 0, 0, 12],
		[MwiEntry.FLAG_SINGLE_ACCESS | MwiEntry.FLAG_MANUAL_COMPRESSION, 7, 3, 8, 9],
	] as Array[Array], ["PACKED\\FIXE_VRAM.VLO", "PACKED\\LEVEL.WAD", "GFX/MODELS/FROG.XAR"] as Array[String])
	var index: MwiIndex = MwiIndexReader.parse(bytes)
	assert_eq(index.error, "")
	assert_eq(index.size(), 4)
	var vlo: MwiEntry = index.get_entry(0)
	assert_eq(vlo.path, "PACKED\\FIXE_VRAM.VLO")
	assert_eq(vlo.display_name(), "FIXE_VRAM.VLO")
	assert_true(vlo.is_single_access())
	assert_true(vlo.is_automatically_compressed())
	assert_true(vlo.is_compressed())
	assert_eq(vlo.archive_offset(), 2048)
	assert_eq(vlo.archive_size(), 100)
	var wad: MwiEntry = index.get_entry(1)
	assert_true(wad.is_wad())
	assert_true(wad.is_group())
	assert_eq(wad.type_id, -1)
	var child: MwiEntry = index.get_entry(2)
	assert_true(child.is_group_access())
	assert_false(child.is_compressed())
	assert_eq(child.archive_size(), 12)
	assert_eq(child.display_name(), "FROG.XAR")
	var unnamed: MwiEntry = index.get_entry(3)
	assert_eq(unnamed.path, "")
	assert_eq(unnamed.display_name(), "File 3")
	assert_true(unnamed.is_manually_compressed())
	assert_eq(index.find_by_name("fixe_vram.vlo"), vlo)
	assert_null(index.find_by_name("nope"))
	assert_null(index.get_entry(4))
	assert_eq(index.wad_entries(), [wad] as Array[MwiEntry])
	assert_eq(index.count_by_type()[-1], 1)
	assert_eq(index.compressed_count(), 3)


func test_mwi_safety_margin_is_the_top_byte() -> void:
	var bytes: PackedByteArray = mwi_record(MwiEntry.NO_NAME, 17, 1, 1, 10, 0x123456, 3)
	var index: MwiIndex = MwiIndexReader.parse(bytes)
	assert_eq(index.get_entry(0).unpacked_size, 0x123456)
	assert_eq(index.get_entry(0).safety_margin_words, 3)


func test_mwi_from_exe_region() -> void:
	var mwi: PackedByteArray = build_mwi([[1, 2, 3, 4, 5]] as Array[Array], ["A.B"] as Array[String])
	var exe := PackedByteArray()
	exe.resize(64)
	exe.append_array(mwi)
	exe.append_array(PackedByteArray([9, 9, 9]))
	var version := GameVersionConfig.new()
	version.mwi_offset = 64
	version.mwi_length = mwi.size()
	var index: MwiIndex = MwiIndexReader.from_exe(exe, version)
	assert_eq(index.error, "")
	assert_eq(index.get_entry(0).path, "A.B")
	version.mwi_length = 9999
	assert_string_contains(MwiIndexReader.from_exe(exe, version).error, "outside")


func test_mwi_errors() -> void:
	assert_string_contains(MwiIndexReader.parse(PackedByteArray([1, 2, 3])).error, "no entries")
	var bad_runtime: PackedByteArray = u32s([MwiEntry.NO_NAME, 1, 1, 1, 5, 0, 1, 1])
	assert_string_contains(MwiIndexReader.parse(bad_runtime).error, "run-time")
	var bad_name: PackedByteArray = mwi_record(32, 1, 1, 1, 1, 1)
	bad_name.append_array("NOTERMINATOR".to_ascii_buffer())
	assert_string_contains(MwiIndexReader.parse(bad_name).error, "terminator")


func test_wad_children() -> void:
	var packed_child: PackedByteArray = Pp20TestPacker.new().pack("hello hello hello hello".to_ascii_buffer())
	var bytes: PackedByteArray = build_wad([[5, 4, "abc".to_ascii_buffer()], [6, 3, packed_child]] as Array[Array])
	var wad: WadFile = WadFileReader.parse(bytes)
	assert_eq(wad.error, "")
	assert_eq(wad.children.size(), 2)
	assert_eq(wad.children[0].resource_id, 5)
	assert_eq(wad.children[0].type_id, 4)
	assert_eq(wad.children[0].data, "abc".to_ascii_buffer())
	assert_false(wad.children[0].is_packed)
	assert_true(wad.children[1].is_packed)
	assert_eq(WadFileReader.child_contents(wad, wad.children[1]), "hello hello hello hello".to_ascii_buffer())
	assert_eq(WadFileReader.child_contents(wad, wad.children[0]), "abc".to_ascii_buffer())


func test_wad_errors() -> void:
	var good: PackedByteArray = build_wad([[5, 4, "abcdefgh".to_ascii_buffer()]] as Array[Array])
	assert_string_contains(WadFileReader.parse(good.slice(0, good.size() - 16)).error, "no end marker")
	var oversize: PackedByteArray = u32s([5, 4, 1000, 0])
	oversize.append_array(u32s([-1, 0, 0, 0]))
	assert_string_contains(WadFileReader.parse(oversize).error, "claims 1000 bytes")
	var dirty_end: PackedByteArray = u32s([-1, 0, 7, 0])
	assert_string_contains(WadFileReader.parse(dirty_end).error, "not zero-filled")
	assert_eq(WadFileReader.parse(u32s([-1, 0, 0, 0])).children.size(), 0)


func _write(path: String, data: PackedByteArray) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


func test_mwd_reads_plain_packed_and_refuses_wad_members() -> void:
	var plain: PackedByteArray = "PLAIN FILE".to_ascii_buffer()
	var original: PackedByteArray = "packed packed packed packed packed".to_ascii_buffer()
	var packed: PackedByteArray = Pp20TestPacker.new().pack(original)
	var mwd: PackedByteArray = "DAWM".to_ascii_buffer()
	mwd.resize(2048 * 3)
	for i: int in plain.size():
		mwd[2048 + i] = plain[i]
	for i: int in packed.size():
		mwd[4096 + i] = packed[i]
	var path: String = ROOT.path_join("TEST.MWD")
	_write(path, mwd)
	var index: MwiIndex = MwiIndexReader.parse(build_mwi([
		[MwiEntry.FLAG_SINGLE_ACCESS, 3, 1, 0, plain.size()],
		[MwiEntry.FLAG_SINGLE_ACCESS | MwiEntry.FLAG_AUTOMATIC_COMPRESSION, 3, 2, packed.size(), original.size()],
		[MwiEntry.FLAG_GROUP_ACCESS, 4, 0, 0, 4],
		[MwiEntry.FLAG_SINGLE_ACCESS, 3, 2, 0, 99999],
		[MwiEntry.FLAG_SINGLE_ACCESS | MwiEntry.FLAG_AUTOMATIC_COMPRESSION, 3, 1, 10, 10],
	] as Array[Array], [] as Array[String]))
	var problems := PackedStringArray()
	var archive: MwdArchive = MwdArchive.open(path, problems)
	assert_not_null(archive, ", ".join(problems))
	assert_eq(archive.read(index.get_entry(0)), plain)
	assert_eq(archive.read(index.get_entry(1)), original)
	assert_eq(archive.read_raw(index.get_entry(1)), packed)
	assert_eq(archive.read(index.get_entry(2)), PackedByteArray())
	assert_string_contains(archive.error, "inside a WAD")
	assert_eq(archive.read(index.get_entry(3)), PackedByteArray())
	assert_string_contains(archive.error, "past the end")
	assert_eq(archive.read(index.get_entry(4)), PackedByteArray())
	assert_string_contains(archive.error, "not PP20")
	archive.close()


func test_mwd_bad_header() -> void:
	var path: String = ROOT.path_join("BAD.MWD")
	_write(path, "MAWD0000".to_ascii_buffer())
	var problems := PackedStringArray()
	assert_null(MwdArchive.open(path, problems))
	assert_string_contains(problems[0], "DAWM")
	var nonzero: PackedByteArray = "DAWM".to_ascii_buffer()
	nonzero.append_array(PackedByteArray([1, 0, 0, 0]))
	_write(path, nonzero)
	problems.clear()
	assert_null(MwdArchive.open(path, problems))
	assert_string_contains(problems[0], "not zero")
	problems.clear()
	assert_null(MwdArchive.open(ROOT.path_join("MISSING.MWD"), problems))
	assert_string_contains(problems[0], "cannot open")
