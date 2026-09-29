class_name MwdArchive
extends RefCounted
## Reads files out of the MWD (Millennium WAD Data) archive, [code]FROGPSX.MWD[/code].
##
## The MWD is the game's one big data file. It starts with the signature
## [code]DAWM[/code] and four zero bytes, then build notes filling the rest of
## the first 2048-byte sector; files follow, each starting on a sector
## boundary. The archive has no directory of its own: where each file is, and
## how big, comes from the [MwiIndex]. FrogLord moves and resizes files when
## it saves, so positions must always come from the loaded index.
##
## The archive is read by seeking, never loaded whole.

## The archive's first four bytes.
const SIGNATURE: String = "DAWM"

## Why the last operation failed, or "".
var error: String = ""

var _file: FileAccess
var _unpacker := Pp20.new()


## Opens the archive at [param path] and checks its header. Returns null
## (with the reason in [param problems] if given) when that fails.
static func open(path: String, problems: PackedStringArray = PackedStringArray()) -> MwdArchive:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		problems.append("cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	return from_file(file, problems)


## Wraps an already opened archive file, checking its header.
static func from_file(file: FileAccess, problems: PackedStringArray = PackedStringArray()) -> MwdArchive:
	file.seek(0)
	var header: PackedByteArray = file.get_buffer(8)
	if header.size() < 8 or header.slice(0, 4) != SIGNATURE.to_ascii_buffer():
		problems.append("not an MWD archive (no '%s' signature)" % SIGNATURE)
		return null
	if header.decode_u32(4) != 0:
		problems.append("unexpected MWD header: bytes 4..7 are not zero")
		return null
	var archive := MwdArchive.new()
	archive._file = file
	return archive


## Size of the archive in bytes.
func size() -> int:
	return _file.get_length()


## The stored (possibly compressed) bytes of [param entry]. Entries that live
## inside a WAD have no data of their own and are refused.
func read_raw(entry: MwiEntry) -> PackedByteArray:
	error = ""
	if entry.is_group_access():
		error = "%s lives inside a WAD; read the WAD instead" % entry.display_name()
		return PackedByteArray()
	var start: int = entry.archive_offset()
	var length: int = entry.archive_size()
	if start + length > _file.get_length():
		error = "%s (%d bytes at %d) runs past the end of the archive (%d bytes)" % [
			entry.display_name(), length, start, _file.get_length()]
		return PackedByteArray()
	_file.seek(start)
	return _file.get_buffer(length)


## The contents of [param entry], decompressed when the index marks it compressed.
func read(entry: MwiEntry) -> PackedByteArray:
	var raw: PackedByteArray = read_raw(entry)
	if not error.is_empty():
		return PackedByteArray()
	if not entry.is_compressed():
		return raw
	if not Pp20.is_packed(raw):
		error = "%s is marked compressed but is not PP20 data" % entry.display_name()
		return PackedByteArray()
	var data: PackedByteArray = _unpacker.unpack(raw)
	if not _unpacker.error.is_empty():
		error = "%s: %s" % [entry.display_name(), _unpacker.error]
		return PackedByteArray()
	if data.size() != entry.unpacked_size:
		error = "%s unpacked to %d bytes, the index says %d" % [entry.display_name(), data.size(), entry.unpacked_size]
		return PackedByteArray()
	return data


## Closes the archive file.
func close() -> void:
	if _file != null:
		_file.close()
		_file = null
