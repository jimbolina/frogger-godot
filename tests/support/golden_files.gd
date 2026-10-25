class_name GoldenFiles
extends RefCounted
## Reads the committed golden facts under tests/golden/ and computes the
## digests they are compared with (see tests/golden/README.md).

## Where the facts about the reference build live.
const GOLDEN_DIR: String = "res://tests/golden/pc-retail-v3.0e"


## Rows of a golden TSV file, split on tabs, comment lines dropped.
static func rows(file_name: String) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	var text: String = FileAccess.get_file_as_string(GOLDEN_DIR.path_join(file_name))
	for line: String in text.split("\n", false):
		if not line.begins_with("#"):
			result.append(line.split("\t"))
	return result


## key=value facts from a golden text file.
static func facts(file_name: String) -> Dictionary[String, String]:
	var result: Dictionary[String, String] = {}
	for line: String in FileAccess.get_file_as_string(GOLDEN_DIR.path_join(file_name)).split("\n", false):
		var at: int = line.find("=")
		result[line.substr(0, at)] = line.substr(at + 1)
	return result


## SHA-256 of [param data] as lower-case hex.
static func sha256_hex(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not data.is_empty():
		ctx.update(data)
	return ctx.finish().hex_encode()


## The golden "list digest": SHA-256 of the decimal values joined by commas.
static func list_digest(values: PackedInt64Array) -> String:
	var parts := PackedStringArray()
	for value: int in values:
		parts.append(str(value))
	return sha256_hex(",".join(parts).to_ascii_buffer())


## [method list_digest] of 32-bit values.
static func list_digest32(values: PackedInt32Array) -> String:
	var wide := PackedInt64Array()
	for value: int in values:
		wide.append(value)
	return list_digest(wide)


## [param value] as upper-case hexadecimal with a 0x prefix, as the goldens write addresses.
static func hex(value: int) -> String:
	return "0x%X" % value


## Compares [param got] with [param want] row by row; returns up to five
## descriptions of differing rows plus a count line, or an empty array.
static func differences(label: String, got: Array[PackedStringArray], want: Array[PackedStringArray]) -> PackedStringArray:
	var out := PackedStringArray()
	var mismatches: int = 0
	if got.size() != want.size():
		out.append("%s: %d rows, golden has %d" % [label, got.size(), want.size()])
	for i: int in mini(got.size(), want.size()):
		if got[i] != want[i]:
			mismatches += 1
			if mismatches <= 5:
				out.append("%s row %d: got %s, golden %s" % [label, i, got[i], want[i]])
	if mismatches > 0:
		out.append("%s: %d rows differ" % [label, mismatches])
	return out
