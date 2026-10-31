class_name ScoreTableReader
extends RefCounted
## Reads the v3.0e SCORE_BOOK records ([ScoreTable]) at the address verified from AddFrogScore.

## In-program address of [code]SCORE_BOOK[/code].
const POINTER: int = 0x472b80
## Records in the table.
const COUNT: int = 24


## Reads original or FrogLord-saved table contents without executing supplied code.
static func read(exe: ExeImage) -> ScoreTable:
	var result := ScoreTable.new()
	if exe.version.internal_name != "pc-retail-v3.0e":
		result.error = "SCORE_BOOK table is unverified for this build"
		return result
	var reader: ByteReader = exe.reader_at_pointer(POINTER)
	for index: int in COUNT:
		result.values.append(reader.read_s32())
		result.texture_pointers.append(reader.read_u32())
		result.flags.append(reader.read_u32())
		if reader.has_error():
			result.error = "SCORE_BOOK[%d] at 0x%X: %s" % [index, POINTER + index * 12, reader.error]
			return result
	return result
