class_name MwiEntry
extends RefCounted
## One resource listed in the MWI (Millennium WAD Index).
##
## Each game file (a texture bank, model, map, sound bank, or a WAD bundle of
## such files) has a numbered entry saying where it is in the MWD archive,
## how big it is, and whether it is PowerPacker-compressed. Frogger's entries
## are 32 bytes:
## [codeblock]
## u32 name offset (from the start of the MWI; 0xFFFFFFFF = no name)
## u32 flags        u32 type id        u32 start sector in the MWD (2048-byte sectors)
## u32 0            u32 0              (filled in by the game at run time)
## u32 packed size  u32 unpacked size (low 24 bits) | safety margin (top 8 bits)
## [/codeblock]

## Bit 0: loaded on its own (a file directly in the MWD).
const FLAG_SINGLE_ACCESS: int = 1 << 0
## Bit 1: loaded as part of a WAD; it has no data of its own in the MWD.
const FLAG_GROUP_ACCESS: int = 1 << 1
## Bit 2: this entry is a WAD (a bundle of other entries).
const FLAG_IS_GROUP: int = 1 << 2
## Bit 3: path is absolute (unused in retail data).
const FLAG_ABSOLUTE_PATH: int = 1 << 3
## Bit 4: compressed automatically by the build tools.
const FLAG_AUTOMATIC_COMPRESSION: int = 1 << 4
## Bit 5: compressed by hand before the build.
const FLAG_MANUAL_COMPRESSION: int = 1 << 5
## Bytes per MWD sector.
const SECTOR_SIZE: int = 2048
## Type id of WAD entries.
const TYPE_WAD: int = -1
## Name offset meaning "no name".
const NO_NAME: int = 0xFFFFFFFF
## Size in bytes of one entry.
const ENTRY_SIZE: int = 32

## Position in the MWI; other data refers to files by this number (resource id).
var index: int = 0
## Path as recorded by the build tools, e.g. "PACKED\\FIXE_VRAM.VLO"; "" if unnamed.
var path: String = ""
## Raw flag bits.
var flags: int = 0
## Type id (-1 for WADs; other values are loosely per file kind).
var type_id: int = 0
## First 2048-byte sector of the file in the MWD.
var sector_offset: int = 0
## Size in the MWD when compressed.
var packed_size: int = 0
## Size after decompression (or the stored size when not compressed).
var unpacked_size: int = 0
## Words of headroom needed to decompress in place (build-tool computed).
var safety_margin_words: int = 0
## Offset of the name inside the MWI, [constant NO_NAME] if none.
var name_offset: int = NO_NAME


## File name without folders, e.g. "FIXE_VRAM.VLO"; "File <index>" when unnamed.
func display_name() -> String:
	if path.is_empty():
		return "File %d" % index
	var name_start: int = maxi(path.rfind("\\"), path.rfind("/")) + 1
	return path.substr(name_start)


## True if this file is loaded on its own.
func is_single_access() -> bool:
	return flags & FLAG_SINGLE_ACCESS != 0


## True if this file lives inside a WAD and has no data of its own in the MWD.
func is_group_access() -> bool:
	return flags & FLAG_GROUP_ACCESS != 0


## True if this entry is a WAD bundle.
func is_group() -> bool:
	return flags & FLAG_IS_GROUP != 0


## True if the absolute-path flag is set.
func has_absolute_path() -> bool:
	return flags & FLAG_ABSOLUTE_PATH != 0


## True if compressed automatically by the build tools.
func is_automatically_compressed() -> bool:
	return flags & FLAG_AUTOMATIC_COMPRESSION != 0


## True if compressed by hand.
func is_manually_compressed() -> bool:
	return flags & FLAG_MANUAL_COMPRESSION != 0


## True if the stored data is PowerPacker-compressed.
func is_compressed() -> bool:
	return flags & (FLAG_AUTOMATIC_COMPRESSION | FLAG_MANUAL_COMPRESSION) != 0


## True if the entry is a WAD (by type id, as the game treats it).
func is_wad() -> bool:
	return type_id == TYPE_WAD


## Byte offset of the file in the MWD.
func archive_offset() -> int:
	return sector_offset * SECTOR_SIZE


## Bytes the file occupies in the MWD.
func archive_size() -> int:
	return packed_size if is_compressed() else unpacked_size
