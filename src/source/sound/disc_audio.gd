class_name DiscAudio
extends RefCounted
## Redbook audio tracks of the player's Alcohol 120% disc image (.mds table, .mdf raw sectors), read per track on request.
##
## The table must describe one session whose track 1 is data and whose later
## tracks are audio, every sector 2352 bytes, laid out contiguously from offset
## 0 with the last track ending exactly at the .mdf's size. Byte positions come
## from each track's start offset, never its start sector, since the image
## stores no pregap sectors. Track PCM is signed 16-bit little-endian stereo at
## [constant SAMPLE_RATE].

const ENVIRONMENT_VARIABLE: String = "FROGGER_DISC"
const ARGUMENT_PREFIX: String = "--disc="
const SIGNATURE: String = "MEDIA DESCRIPTOR"
const SECTOR_BYTES: int = 2352
const SAMPLE_RATE: int = 44100
const MODE_DATA: int = 0xEC
const MODE_AUDIO: int = 0xA9
const MAX_TRACKS: int = 99
const MAX_TRACK_BYTES: int = 64 * 1024 * 1024
const MAX_TABLE_BYTES: int = 1 << 20
const SESSION_BYTES: int = 24
const TRACK_BYTES: int = 80
const EXTRA_BYTES: int = 8

## One real track row of the table.
class Track:
	extends RefCounted
	var number: int = 0
	var mode: int = 0
	var sector_size: int = 0
	var start_sector: int = 0
	var start_offset: int = 0
	var pregap: int = 0
	var length: int = 0

	## Byte length of the track's raw sectors.
	func byte_length() -> int:
		return length * SECTOR_BYTES

var tracks: Array[Track] = []
var mds_path: String = ""
var mdf_path: String = ""
var error: String = ""

## Opens the disc named by a [code]--disc=[/code] argument, else [param environment_value]; an error names an absent or invalid image.
static func locate(arguments: PackedStringArray, environment_value: String) -> DiscAudio:
	var chosen: String = environment_value
	for argument: String in arguments:
		if argument.begins_with(ARGUMENT_PREFIX):
			chosen = argument.substr(ARGUMENT_PREFIX.length())
	if chosen.is_empty():
		var absent := DiscAudio.new()
		absent.error = "No disc image supplied (%s<path> or %s)" % [ARGUMENT_PREFIX, ENVIRONMENT_VARIABLE]
		return absent
	return open(chosen)

## Opens a .mds file, its .mdf, or a folder holding them, validating the table against the .mdf's size.
static func open(path: String) -> DiscAudio:
	var mds: String = _find_mds(path)
	if mds.is_empty():
		var missing := DiscAudio.new()
		missing.error = "No .mds disc table found at %s" % path
		return missing
	var file: FileAccess = FileAccess.open(mds, FileAccess.READ)
	if file == null or file.get_length() > MAX_TABLE_BYTES:
		var unreadable := DiscAudio.new()
		unreadable.error = "Disc table %s is unreadable" % mds
		return unreadable
	var result: DiscAudio = parse_mds(file.get_buffer(file.get_length()))
	file.close()
	result.mds_path = mds
	if not result.error.is_empty():
		result.error = "%s: %s" % [mds, result.error]
		return result
	result.mdf_path = _find_mdf(mds)
	if result.mdf_path.is_empty():
		result.error = "Disc image %s has no .mdf beside it" % mds
		return result
	var image: FileAccess = FileAccess.open(result.mdf_path, FileAccess.READ)
	if image == null:
		result.error = "Disc image %s is unreadable" % result.mdf_path
		return result
	var last: Track = result.tracks[result.tracks.size() - 1]
	if image.get_length() != last.start_offset + last.byte_length():
		result.error = "Disc image %s is %d bytes, but its table ends at %d" % [result.mdf_path, image.get_length(), last.start_offset + last.byte_length()]
	image.close()
	return result

## Parses and validates a .mds table; tracks are kept only when every check passes.
static func parse_mds(bytes: PackedByteArray) -> DiscAudio:
	var result := DiscAudio.new()
	result.error = _parse(bytes, result.tracks)
	if not result.error.is_empty():
		result.tracks.clear()
	return result

## The table row for audio or data [param number], or [code]null[/code].
func track(number: int) -> Track:
	return tracks[number - 1] if number >= 1 and number <= tracks.size() else null

## Reads audio track [param number]'s raw stereo PCM from the .mdf; empty with [member error] set on failure.
func read_track(number: int) -> PackedByteArray:
	var row: Track = track(number)
	if row == null or row.mode != MODE_AUDIO:
		error = "Disc track %d is not an audio track" % number
		return PackedByteArray()
	var image: FileAccess = FileAccess.open(mdf_path, FileAccess.READ) if not mdf_path.is_empty() else null
	if image == null:
		error = "Disc image %s is unreadable" % mdf_path
		return PackedByteArray()
	image.seek(row.start_offset)
	var pcm: PackedByteArray = image.get_buffer(row.byte_length())
	image.close()
	if pcm.size() != row.byte_length():
		error = "Disc track %d read %d of %d bytes" % [number, pcm.size(), row.byte_length()]
		return PackedByteArray()
	return pcm

static func _parse(bytes: PackedByteArray, out: Array[Track]) -> String:
	if bytes.size() < 0x58 or bytes.slice(0, 16).get_string_from_ascii() != SIGNATURE:
		return "not a Media Descriptor table"
	if bytes[0x10] != 1 or bytes[0x11] != 5:
		return "unsupported table version %d.%d" % [bytes[0x10], bytes[0x11]]
	if bytes.decode_u16(0x12) != 1:
		return "medium is not a CD"
	if bytes.decode_u16(0x14) != 1:
		return "exactly one session is required"
	var session: int = bytes.decode_u32(0x50)
	if session <= 0 or session + SESSION_BYTES > bytes.size():
		return "session block lies outside the table"
	var block_count: int = bytes[session + 0x0A]
	var first_track: int = bytes.decode_u16(session + 0x0C)
	var last_track: int = bytes.decode_u16(session + 0x0E)
	var blocks: int = bytes.decode_u32(session + 0x14)
	if block_count <= 0 or blocks <= 0 or blocks + block_count * TRACK_BYTES > bytes.size():
		return "track blocks lie outside the table"
	for index: int in block_count:
		var block: int = blocks + index * TRACK_BYTES
		var point: int = bytes[block + 0x04]
		if point >= 0xA0 and point <= 0xA2:
			continue
		if out.size() >= MAX_TRACKS:
			return "more than %d tracks" % MAX_TRACKS
		var extra: int = bytes.decode_u32(block + 0x0C)
		if extra <= 0 or extra + EXTRA_BYTES > bytes.size():
			return "track point %d has no extra block" % point
		var row := Track.new()
		row.number = point
		row.mode = bytes[block]
		row.sector_size = bytes.decode_u16(block + 0x10)
		row.start_sector = bytes.decode_s32(block + 0x24)
		row.start_offset = bytes.decode_u64(block + 0x28)
		row.pregap = bytes.decode_u32(extra)
		row.length = bytes.decode_u32(extra + 4)
		out.append(row)
	if out.size() < 2:
		return "a data track and at least one audio track are required"
	for index: int in out.size():
		var row: Track = out[index]
		if row.number != index + 1:
			return "track points are not 1 to %d in order" % out.size()
		if row.mode != (MODE_DATA if index == 0 else MODE_AUDIO):
			return "track %d has mode 0x%X" % [row.number, row.mode]
		if row.sector_size != SECTOR_BYTES:
			return "track %d sectors are %d bytes" % [row.number, row.sector_size]
		if row.length <= 0 or (index > 0 and row.byte_length() > MAX_TRACK_BYTES):
			return "track %d has an invalid length" % row.number
		var expected: int = 0 if index == 0 else out[index - 1].start_offset + out[index - 1].byte_length()
		if row.start_offset != expected:
			return "track %d starts at %d, not contiguously at %d" % [row.number, row.start_offset, expected]
	if first_track != 1 or last_track != out.size():
		return "session range %d-%d does not match %d tracks" % [first_track, last_track, out.size()]
	return ""

static func _find_mds(path: String) -> String:
	if DirAccess.dir_exists_absolute(path):
		var names: PackedStringArray = DirAccess.get_files_at(path)
		names.sort()
		for file_name: String in names:
			if file_name.get_extension().to_lower() == "mds":
				return path.path_join(file_name)
		return ""
	if path.get_extension().to_lower() == "mdf":
		for extension: String in ["mds", "MDS"]:
			var sibling: String = path.get_basename() + "." + extension
			if FileAccess.file_exists(sibling):
				return sibling
		return ""
	return path if FileAccess.file_exists(path) else ""

static func _find_mdf(mds: String) -> String:
	for extension: String in ["mdf", "MDF"]:
		var sibling: String = mds.get_basename() + "." + extension
		if FileAccess.file_exists(sibling):
			return sibling
	return ""
