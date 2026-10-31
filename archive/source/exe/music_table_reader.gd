class_name MusicTableReader
extends RefCounted
## Reads the per-level music list ([MusicTable]) from the executable.


## Reads the music list of [param exe], up to its 0xFF end marker.
static func read(exe: ExeImage) -> MusicTable:
	var table := MusicTable.new()
	if exe.version.music_address <= 0:
		table.error = "this build has no music list address"
		return table
	var reader: ByteReader = exe.reader_at(exe.version.music_address)
	while true:
		var value: int = reader.read_u8()
		if reader.has_error():
			table.error = "music list has no end marker: %s" % reader.error
			break
		if value == MusicTable.TERMINATOR:
			break
		table.tracks.append(value)
	return table
