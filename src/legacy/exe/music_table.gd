class_name MusicTable
extends RefCounted
## The music list: the CD audio track played on each level, by level number.
##
## One byte per level, ended by 0xFF (FrogLord's [code]readMusicData[/code]).
## On the PC release the values are track numbers of the game CD (2 to 21);
## [FroggerIds] has FrogLord's names for them. An unknown number is kept as
## read, so an edited executable still loads.

## The byte that ends the list.
const TERMINATOR: int = 0xFF

## Track number per level, in level order.
var tracks: PackedInt32Array = PackedInt32Array()
## Why reading failed, or "".
var error: String = ""


## Reads the music list of [param exe].
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
		if value == TERMINATOR:
			break
		table.tracks.append(value)
	return table


## Number of levels listed.
func size() -> int:
	return tracks.size()


## The track number for level [param level], or -1 when the level is not listed.
func track_for_level(level: int) -> int:
	return tracks[level] if level >= 0 and level < tracks.size() else -1
