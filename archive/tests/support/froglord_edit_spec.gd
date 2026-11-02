class_name FrogLordEditSpec
extends RefCounted
## The shared edit specification of the FrogLord round trip,
## [code]tests/golden/synthetic/froglord_edits.tsv[/code].
##
## One tab-separated row per edit with six columns: kind, target, subject,
## field, value and note. Lines starting with [code]#[/code] and blank lines
## are skipped. The value is decimal or [code]0x[/code] hexadecimal.
## [codeblock]
## form    <theme>      <form name>   <form field>  <value>
## script  <script>     <word index>  word          <value>
## remap   <remap>      <slot>        slot          <value>
## demo    <file name>  <input index> input         <value>
## map     <file name>  <entity>      <entity field> <value>
## [/codeblock]
## See [code]tests/golden/specs/imported-assets.md[/code].

## The edit kinds, in the order the specification documents them.
const KINDS: PackedStringArray = ["form", "script", "remap", "demo", "map"]
## Columns of every row.
const COLUMNS: int = 6


## One edit.
class Row:
	extends RefCounted
	## One of [constant KINDS].
	var kind: String = ""
	## The theme, script, remap or archive file name.
	var target: String = ""
	## The form name, or the word, slot, input or entity index as text.
	var subject: String = ""
	## The changed field.
	var field: String = ""
	## The new value.
	var value: int = 0
	## Why the edit was chosen.
	var note: String = ""
	## The row's line in the file, from 1.
	var line: int = 0

	## The subject as an index; -1 when it is not a number.
	func index() -> int:
		return subject.to_int() if subject.is_valid_int() else -1

	## A short description naming the edit, for messages.
	func describe() -> String:
		return "%s %s %s %s" % [kind, target, subject, field]


## The rows in file order.
var rows: Array[Row] = []
## Why the file could not be read, or "".
var error: String = ""


## Reads the specification at [param path].
static func read(path: String) -> FrogLordEditSpec:
	if not FileAccess.file_exists(path):
		var missing := FrogLordEditSpec.new()
		missing.error = "no edit specification at %s" % path
		return missing
	return parse(FileAccess.get_file_as_string(path))


## Parses specification [param text].
static func parse(text: String) -> FrogLordEditSpec:
	var spec := FrogLordEditSpec.new()
	var lines: PackedStringArray = text.split("\n")
	for number: int in lines.size():
		var line: String = lines[number].trim_suffix("\r")
		if line.strip_edges().is_empty() or line.begins_with("#"):
			continue
		var cells: PackedStringArray = line.split("\t")
		if cells.size() != COLUMNS:
			spec.error = "line %d has %d columns, not %d" % [number + 1, cells.size(), COLUMNS]
			return spec
		if not KINDS.has(cells[0]):
			spec.error = "line %d: unknown kind %s" % [number + 1, cells[0]]
			return spec
		var value_text: String = cells[4]
		var negative: bool = value_text.begins_with("-")
		var digits: String = value_text.trim_prefix("-")
		var is_hex: bool = digits.to_lower().begins_with("0x") and digits.substr(2).is_valid_hex_number()
		if not is_hex and not digits.is_valid_int():
			spec.error = "line %d: value %s is not a number" % [number + 1, value_text]
			return spec
		var row := Row.new()
		row.kind = cells[0]
		row.target = cells[1]
		row.subject = cells[2]
		row.field = cells[3]
		row.value = digits.substr(2).hex_to_int() if is_hex else digits.to_int()
		if negative:
			row.value = -row.value
		row.note = cells[5]
		row.line = number + 1
		spec.rows.append(row)
	return spec


## The rows of [param kind], in file order.
func of_kind(kind: String) -> Array[Row]:
	var found: Array[Row] = []
	for row: Row in rows:
		if row.kind == kind:
			found.append(row)
	return found


## The distinct targets of the rows of [param kind]; for forms, the form names.
func names_of(kind: String) -> PackedStringArray:
	var found := PackedStringArray()
	for row: Row in of_kind(kind):
		var key: String = row.subject if kind == "form" else row.target
		if not found.has(key):
			found.append(key)
	return found
