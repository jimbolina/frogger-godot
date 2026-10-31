class_name MusicTable
extends Resource
## The music list: the CD audio track played on each level, by level number.
##
## One byte per level, ended by 0xFF (FrogLord's [code]readMusicData[/code]).
## On the PC release the values are track numbers of the game CD (2 to 21);
## [FroggerIds] has FrogLord's names for them. An unknown number is kept as
## read, so an edited executable still loads.

## The byte that ends the list.
const TERMINATOR: int = 0xFF

## Track number per level, in level order.
@export var tracks: PackedInt32Array = PackedInt32Array()
## Why reading failed, or "".
@export var error: String = ""


## Reads the music list of [param exe] (see [MusicTableReader]).
static func read(exe: ExeImage) -> MusicTable:
	return MusicTableReader.read(exe)


## Number of levels listed.
func size() -> int:
	return tracks.size()


## The track number for level [param level], or -1 when the level is not listed.
func track_for_level(level: int) -> int:
	return tracks[level] if level >= 0 and level < tracks.size() else -1
