extends RetailTest
## Needs the retail files: every MWI entry, MWD resource and WAD child matches
## the golden manifest in tests/golden/pc-retail-v3.0e/ (made by an independent
## Python reader, see tests/golden/README.md).

const GOLDEN_DIR: String = "res://tests/golden/pc-retail-v3.0e"

var _version: GameVersionConfig
var _index: MwiIndex


func before_all() -> void:
	if not retail_skip_reason().is_empty():
		return
	_version = FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e")
	var started: int = Time.get_ticks_usec()
	_index = MwiIndex.from_exe(retail_source().get_exe_bytes(), _version)
	print("TIMING: MWI parse %.1f ms (%d entries)" % [(Time.get_ticks_usec() - started) / 1000.0, _index.size()])


## Rows of a golden TSV file, split on tabs, comment lines dropped.
static func golden_rows(file_name: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var text: String = FileAccess.get_file_as_string(GOLDEN_DIR.path_join(file_name))
	for line: String in text.split("\n", false):
		if not line.begins_with("#"):
			rows.append(line.split("\t"))
	return rows


## key=value facts from summary.txt.
static func golden_summary() -> Dictionary[String, String]:
	var facts: Dictionary[String, String] = {}
	for line: String in FileAccess.get_file_as_string(GOLDEN_DIR.path_join("summary.txt")).split("\n", false):
		var at: int = line.find("=")
		facts[line.substr(0, at)] = line.substr(at + 1)
	return facts


static func sha256_hex(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()


func _open_archive() -> MwdArchive:
	var problems := PackedStringArray()
	var archive: MwdArchive = MwdArchive.open(retail_source().get_mwd_path(), problems)
	assert_not_null(archive, ", ".join(problems))
	return archive


func test_file_facts() -> void:
	var facts: Dictionary[String, String] = golden_summary()
	var exe: PackedByteArray = retail_source().get_exe_bytes()
	assert_eq(str(exe.size()), facts["exe_size"])
	assert_eq(str(Crc32.of_bytes(exe)), facts["exe_crc32"])
	assert_eq(sha256_hex(exe), facts["exe_sha256"])
	var archive: MwdArchive = _open_archive()
	assert_eq(str(archive.size()), facts["mwd_size"])
	archive.close()
	assert_eq(str(_version.mwi_offset), facts["mwi_offset"])
	assert_eq(str(_version.mwi_length), facts["mwi_length"])


func test_counts() -> void:
	var facts: Dictionary[String, String] = golden_summary()
	assert_eq(_index.error, "")
	assert_eq(str(_index.size()), facts["mwi_entries"])
	assert_eq(str(_index.wad_entries().size()), facts["wads"])
	assert_eq(str(_index.compressed_count()), facts["compressed_resources"])
	var by_type: Dictionary[int, int] = _index.count_by_type()
	for type_id: int in by_type:
		assert_eq(str(by_type[type_id]), facts["entries_of_type[%d]" % type_id])


func test_every_mwi_entry_matches() -> void:
	var rows: Array[PackedStringArray] = golden_rows("mwi_entries.tsv")
	assert_eq(rows.size(), _index.size())
	var mismatches: int = 0
	for row: PackedStringArray in rows:
		var e: MwiEntry = _index.get_entry(row[0].to_int())
		var got := PackedStringArray([str(e.index), e.path, str(e.type_id), str(e.flags), str(e.sector_offset),
			str(e.packed_size), str(e.unpacked_size), str(e.safety_margin_words)])
		if got != row.slice(0, 8):
			mismatches += 1
			if mismatches <= 5:
				fail_test("entry %s: got %s, golden %s" % [row[0], got, row.slice(0, 8)])
	assert_eq(mismatches, 0, "MWI entries differing from the golden manifest")


func test_every_mwd_resource_matches() -> void:
	var rows: Array[PackedStringArray] = golden_rows("mwi_entries.tsv")
	var archive: MwdArchive = _open_archive()
	var checked: int = 0
	var mismatches: int = 0
	var unpack_usec: int = 0
	var read_usec: int = 0
	var unpacked_bytes: int = 0
	var unpacker := Pp20.new()
	for row: PackedStringArray in rows:
		var e: MwiEntry = _index.get_entry(row[0].to_int())
		if e.is_group_access():
			continue
		var t0: int = Time.get_ticks_usec()
		var raw: PackedByteArray = archive.read_raw(e)
		var t1: int = Time.get_ticks_usec()
		var data: PackedByteArray = raw
		if e.is_compressed():
			data = unpacker.unpack(raw)
			unpack_usec += Time.get_ticks_usec() - t1
			unpacked_bytes += data.size()
		read_usec += t1 - t0
		checked += 1
		if sha256_hex(data) != row[9]:
			mismatches += 1
			if mismatches <= 5:
				fail_test("%s (%s): hash differs from the golden manifest (%s)" % [row[0], e.display_name(), unpacker.error])
	archive.close()
	print("TIMING: read %d MWD resources %.0f ms; PP20 unpacked %d compressed resources (%.1f MB) in %.0f ms" % [
		checked, read_usec / 1000.0, _index.compressed_count(), unpacked_bytes / 1048576.0, unpack_usec / 1000.0])
	assert_eq(checked, golden_summary()["mwd_resources"].to_int())
	assert_eq(mismatches, 0, "MWD resources differing from the golden manifest")


func test_every_wad_child_matches() -> void:
	var rows: Array[PackedStringArray] = golden_rows("wad_children.tsv")
	var archive: MwdArchive = _open_archive()
	var got_rows: Array[PackedStringArray] = []
	for wad_entry: MwiEntry in _index.wad_entries():
		var wad: WadFile = WadFile.parse(archive.read(wad_entry))
		assert_eq(wad.error, "", wad_entry.display_name())
		for position: int in wad.children.size():
			var child: WadFile.Child = wad.children[position]
			var contents: PackedByteArray = wad.child_contents(child)
			var child_entry: MwiEntry = WadFile.entry_for(child, _index)
			assert_not_null(child_entry)
			if child_entry != null:
				assert_eq(child_entry.is_compressed(), child.is_packed)
			got_rows.append(PackedStringArray([str(wad_entry.index), str(position), str(child.resource_id),
				str(child.type_id), str(child.data.size()), str(child.file_count), str(int(child.is_packed)),
				str(contents.size()), sha256_hex(contents)]))
	archive.close()
	assert_eq(got_rows.size(), rows.size())
	var mismatches: int = 0
	for i: int in mini(rows.size(), got_rows.size()):
		if got_rows[i] != rows[i]:
			mismatches += 1
			if mismatches <= 5:
				fail_test("WAD child row %d: got %s, golden %s" % [i, got_rows[i], rows[i]])
	assert_eq(mismatches, 0, "WAD children differing from the golden manifest")


func test_group_entries_hash_like_their_wad_copies() -> void:
	var digest_by_id: Dictionary[String, String] = {}
	for row: PackedStringArray in golden_rows("wad_children.tsv"):
		digest_by_id[row[2]] = row[8]
	var missing: int = 0
	for row: PackedStringArray in golden_rows("mwi_entries.tsv"):
		var e: MwiEntry = _index.get_entry(row[0].to_int())
		if e.is_group_access() and digest_by_id.get(row[0], "") != row[9]:
			missing += 1
	assert_eq(missing, 0, "every WAD member's golden hash is the hash of its WAD copy")
