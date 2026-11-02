class_name FrogLordMwdWriter
extends RefCounted
## Writes the files FrogLord saves for a modded retail install, for the
## round-trip fixture.
##
## The archive copies the retail MWD's first sector (signature and build
## notes), then writes every entry that has data of its own in MWI index
## order, each from a 2048-byte sector boundary and padded with zeros to the
## next one. Entries that live only inside a WAD have no data and are
## skipped. An edited entry whose index flags say compressed is packed again
## as PowerPacker data (literals only); an edited stored entry is written as
## it is; every other entry keeps its stored bytes. Each entry's MWI record
## in the executable gets its new sector, packed size and unpacked size, the
## safety-margin byte kept. The index region is also written as the
## standalone [code]modded_FROGPSX.MWI[/code], and the executable gets
## FrogLord's trailer ([FrogLordExeTrailer]) naming the build, with the demo
## table's address as FrogLord records it.

## The FrogLord version the trailer names (FrogLord's own update number).
const FROGLORD_VERSION: int = 1
## The game type the trailer names.
const GAME_TYPE: String = "frogger"

## The executable as written, trailer included.
var exe_bytes: PackedByteArray = PackedByteArray()
## Why the files could not be written, or "".
var error: String = ""


## Writes [code]modded_FROGGER.EXE[/code], [code]modded_FROGPSX.MWD[/code]
## and [code]modded_FROGPSX.MWI[/code] into [param out_dir] from the retail
## [param data], the patched executable [param patched_exe] (no trailer) and
## the edited files' unpacked contents [param files] by MWI index.
static func write(data: GameData, patched_exe: PackedByteArray, files: Dictionary[int, PackedByteArray], out_dir: String) -> FrogLordMwdWriter:
	var writer := FrogLordMwdWriter.new()
	writer.exe_bytes = patched_exe.duplicate()
	writer.error = writer._write_archive(data, files, out_dir.path_join(FrogLordModSource.MWD_NAME))
	if not writer.error.is_empty():
		return writer
	var mwi_start: int = data.version.mwi_offset
	writer.error = _store(out_dir.path_join(FrogLordModSource.MWI_NAME), writer.exe_bytes.slice(mwi_start, mwi_start + data.version.mwi_length))
	if not writer.error.is_empty():
		return writer
	var program_length: int = writer.exe_bytes.size()
	writer.exe_bytes.append_array(FrogLordExeTrailer.build_footer(build_info_text(data), program_length))
	writer.error = _store(out_dir.path_join(FrogLordModSource.EXE_NAME), writer.exe_bytes)
	return writer


## The build information FrogLord appends for [param data]: the demo table's
## address and detail lists at the top level, then the [code][BuildInfo][/code] section.
static func build_info_text(data: GameData) -> String:
	var text: String = ""
	var demos: DemoTable = data.tables.demo_table()
	if demos.file_offset > 0:
		text += "demoTableAddress=0x%X\n" % demos.file_offset
		if demos.has_low_poly_list:
			text += "lowPolyDemoTable=true\n"
	return text + "[BuildInfo]\ngameType=%s\ngameVersion=%s\nfrogLordVersion=%d\n" % [GAME_TYPE, data.version.internal_name, FROGLORD_VERSION]


func _write_archive(data: GameData, files: Dictionary[int, PackedByteArray], path: String) -> String:
	var source: FileAccess = FileAccess.open(data.source.get_mwd_path(), FileAccess.READ)
	if source == null:
		return "cannot open the retail archive %s" % data.source.get_mwd_path()
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		return "cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
	out.store_buffer(source.get_buffer(MwiEntry.SECTOR_SIZE))
	var packer := Pp20TestPacker.new()
	for entry: MwiEntry in data.mwi.entries:
		if entry.is_group_access():
			continue
		var stored: PackedByteArray
		var packed_size: int = entry.packed_size
		var unpacked_size: int = entry.unpacked_size
		if files.has(entry.index):
			var contents: PackedByteArray = files[entry.index]
			stored = packer.pack(contents, 700, true) if entry.is_compressed() else contents
			packed_size = stored.size()
			unpacked_size = contents.size()
		else:
			source.seek(entry.archive_offset())
			stored = source.get_buffer(entry.archive_size())
			if stored.size() != entry.archive_size():
				return "the retail archive ends inside %s" % entry.display_name()
		var sector: int = out.get_position() / MwiEntry.SECTOR_SIZE
		out.store_buffer(stored)
		var padding: int = (MwiEntry.SECTOR_SIZE - stored.size() % MwiEntry.SECTOR_SIZE) % MwiEntry.SECTOR_SIZE
		if padding > 0:
			var zeros := PackedByteArray()
			zeros.resize(padding)
			out.store_buffer(zeros)
		var record: int = data.version.mwi_offset + MwiEntry.ENTRY_SIZE * entry.index
		exe_bytes.encode_u32(record + 12, sector)
		exe_bytes.encode_u32(record + 24, packed_size)
		exe_bytes.encode_u32(record + 28, (unpacked_size & 0xFFFFFF) | (entry.safety_margin_words << 24))
	out.close()
	source.close()
	return ""


static func _store(path: String, bytes: PackedByteArray) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
	file.store_buffer(bytes)
	file.close()
	return ""
