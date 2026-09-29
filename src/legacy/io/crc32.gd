class_name Crc32
extends RefCounted
## The standard CRC-32 (IEEE 802.3, reflected polynomial 0xEDB88320).
##
## FrogLord identifies a game executable by the CRC-32 of the whole file (the
## [code]exeChecksum[/code] key of its version configs). Godot's
## [HashingContext] offers MD5 and SHA only, so this class provides the CRC.

static var _table: PackedInt64Array = PackedInt64Array()


## CRC-32 of [param data], as an unsigned value (the form FrogLord's configs use).
static func of_bytes(data: PackedByteArray) -> int:
	return update(0, data)


## Continues a CRC-32 over [param data], starting from a previous result
## [param crc] (0 for a fresh checksum). Lets large inputs be fed in chunks.
static func update(crc: int, data: PackedByteArray) -> int:
	if _table.is_empty():
		_build_table()
	var table: PackedInt64Array = _table
	var c: int = crc ^ 0xFFFFFFFF
	for b: int in data:
		c = table[(c ^ b) & 0xFF] ^ (c >> 8)
	return c ^ 0xFFFFFFFF


static func _build_table() -> void:
	_table.resize(256)
	for n: int in 256:
		var c: int = n
		for _k: int in 8:
			if c & 1:
				c = 0xEDB88320 ^ (c >> 1)
			else:
				c = c >> 1
		_table[n] = c
