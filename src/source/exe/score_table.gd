class_name ScoreTable
extends RefCounted
## v3.0e SCORE_BOOK records verified from AddFrogScore's table access.

var values: PackedInt32Array = PackedInt32Array()
var flags: PackedInt32Array = PackedInt32Array()
var texture_pointers: PackedInt64Array = PackedInt64Array()
var error: String = ""

## Reads original or FrogLord-saved table contents without executing supplied code.
static func read(exe: ExeImage) -> ScoreTable:
	var result := ScoreTable.new()
	if exe.version.internal_name != "pc-retail-v3.0e":
		result.error = "SCORE_BOOK table is unverified for this build"
		return result
	var reader: ByteReader = exe.reader_at_pointer(0x472b80)
	for index: int in 24:
		result.values.append(reader.read_s32())
		result.texture_pointers.append(reader.read_u32())
		result.flags.append(reader.read_u32())
		if reader.has_error():
			result.error = "SCORE_BOOK[%d] at 0x%X: %s" % [index, 0x472b80 + index * 12, reader.error]
			return result
	return result
