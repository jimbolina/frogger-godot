class_name FrogLordExePatcher
extends RefCounted
## Applies a [FrogLordEditSpec] to the retail files the way a FrogLord edit
## would change them, for the round-trip fixture.
##
## Names resolve through the archive readers of the retail [GameData]: a form
## through its theme's form library, a script through the script table, a
## remap through the remap list, and a demo or map through the archive index
## (a map entity through the decoded EMTP records). Form, script and remap
## edits patch the executable bytes; demo and map edits patch the unpacked
## contents of their archive file. Values are little-endian at the field's
## width: form fields 32-bit (callbacks unsigned), script words signed 32-bit,
## remap slots signed 16-bit, demo inputs unsigned 8-bit and map entity
## fields unsigned 16-bit.

## Byte offset and width of each form field inside its 32-byte library entry.
const FORM_FIELDS: Dictionary[String, Array] = {
	"entity_type": [0, "s32"],
	"model_id": [4, "s32"],
	"script_id": [8, "s32"],
	"flags": [12, "s32"],
	"collision_callback": [16, "u32"],
	"radius_squared": [20, "s32"],
	"death_type": [24, "s32"],
	"bonus_callback": [28, "u32"],
}
## Byte offset and width of each map entity field inside its record.
const MAP_FIELDS: Dictionary[String, Array] = {
	"form_grid_id": [0, "u16"],
	"unique_id": [2, "u16"],
	"form_id": [4, "u16"],
	"flags": [6, "u16"],
}
## Bytes, lowest and highest value of each field width.
const WIDTHS: Dictionary[String, Array] = {
	"s32": [4, -0x80000000, 0x7FFFFFFF],
	"u32": [4, 0, 0xFFFFFFFF],
	"s16": [2, -0x8000, 0x7FFF],
	"u16": [2, 0, 0xFFFF],
	"u8": [1, 0, 0xFF],
}
## The resource column of an edit that lands in the executable.
const EXE_RESOURCE: String = "exe"

## The patched executable, without a FrogLord trailer.
var exe_bytes: PackedByteArray = PackedByteArray()
## The edited archive files' unpacked contents, by MWI index.
var files: Dictionary[int, PackedByteArray] = {}
## One row per edit in the golden [code]edit[/code] schema: kind, target,
## subject, field, resource ([constant EXE_RESOURCE] or the MWI index), the
## offset in the executable or unpacked file, the old and the new value.
var edits: Array[PackedStringArray] = []
## Why an edit could not be applied, or "".
var error: String = ""

var _patched: PackedByteArray = PackedByteArray()


## Applies every row of [param spec] to the files of [param data].
static func apply(data: GameData, spec: FrogLordEditSpec) -> FrogLordExePatcher:
	var patcher := FrogLordExePatcher.new()
	patcher.exe_bytes = data.exe.bytes.slice(0, data.exe.program_length)
	for row: FrogLordEditSpec.Row in spec.rows:
		var issue: String = patcher._apply_row(data, row)
		if not issue.is_empty():
			patcher.error = "line %d (%s): %s" % [row.line, row.describe(), issue]
			return patcher
	return patcher


func _apply_row(data: GameData, row: FrogLordEditSpec.Row) -> String:
	match row.kind:
		"form":
			return _patch_form(data, row)
		"script":
			return _patch_script(data, row)
		"remap":
			return _patch_remap(data, row)
		"demo", "map":
			return _patch_file(data, row)
	return "unknown kind"


func _patch_form(data: GameData, row: FrogLordEditSpec.Row) -> String:
	var theme: int = FroggerIds.THEMES.find(row.target)
	var entry: ThemeBookEntry = data.tables.theme_book().get_entry(theme) if theme >= 0 else null
	if entry == null:
		return "no theme %s" % row.target
	if not FORM_FIELDS.has(row.field):
		return "unknown form field"
	for form: FormBookEntry in entry.forms:
		if form.form_name == row.subject:
			var field_at: int = FORM_FIELDS[row.field][0]
			var at: int = data.exe.pointer_to_offset(entry.form_library_pointer) + FormBookEntry.SIZE * form.local_id + field_at
			return _patch_exe(at, str(FORM_FIELDS[row.field][1]), row)
	return "no form %s in %s" % [row.subject, row.target]


func _patch_script(data: GameData, row: FrogLordEditSpec.Row) -> String:
	if row.field != "word":
		return "a script edit changes a word"
	for script: EntityScript in data.tables.scripts().scripts:
		if script.name == row.target:
			if row.index() < 0 or row.index() >= script.words().size():
				return "%s has %d words" % [row.target, script.words().size()]
			return _patch_exe(data.exe.pointer_to_offset(script.pointer) + 4 * row.index(), "s32", row)
	return "no script %s" % row.target


func _patch_remap(data: GameData, row: FrogLordEditSpec.Row) -> String:
	var remap: TextureRemap = data.tables.remaps().find_by_name(row.target)
	if remap == null:
		return "no remap %s" % row.target
	if row.field != "slot" or row.index() < 0 or row.index() >= remap.size():
		return "%s has %d slots" % [row.target, remap.size()]
	return _patch_exe(remap.file_offset + 2 * row.index(), "s16", row)


func _patch_file(data: GameData, row: FrogLordEditSpec.Row) -> String:
	var entry: MwiEntry = data.mwi.find_by_name(row.target)
	if entry == null:
		return "no archive file %s" % row.target
	if not files.has(entry.index):
		var problems := PackedStringArray()
		files[entry.index] = data.read_resource(entry.index, problems)
		if not problems.is_empty():
			return "; ".join(problems)
	var contents: PackedByteArray = files[entry.index]
	var at: int = -1
	var width: String = ""
	if row.kind == "demo":
		if row.field != "input" or row.index() < 0 or row.index() >= contents.size() - 12:
			return "%s has %d inputs" % [row.target, contents.size() - 12]
		at = 12 + row.index()
		width = "u8"
	else:
		var map: MapFile = MapFileReader.read(contents)
		if not map.error.is_empty():
			return map.error
		if not MAP_FIELDS.has(row.field) or row.index() < 0 or row.index() >= map.entities.size():
			return "%s has %d entities" % [row.target, map.entities.size()]
		var field_at: int = MAP_FIELDS[row.field][0]
		at = map.entities[row.index()].source_offset + field_at
		width = str(MAP_FIELDS[row.field][1])
	var issue: String = _patch(contents, at, width, row, str(entry.index))
	if issue.is_empty():
		files[entry.index] = _patched
	return issue


func _patch_exe(at: int, width: String, row: FrogLordEditSpec.Row) -> String:
	var issue: String = _patch(exe_bytes, at, width, row, EXE_RESOURCE)
	if issue.is_empty():
		exe_bytes = _patched
	return issue


func _patch(bytes: PackedByteArray, at: int, width: String, row: FrogLordEditSpec.Row, resource: String) -> String:
	var size: int = WIDTHS[width][0]
	if at < 0 or at + size > bytes.size():
		return "offset %d is outside the %d bytes" % [at, bytes.size()]
	var lowest: int = WIDTHS[width][1]
	var highest: int = WIDTHS[width][2]
	if row.value < lowest or row.value > highest:
		return "value %d does not fit %s" % [row.value, width]
	_patched = bytes.duplicate()
	var old: int = 0
	match width:
		"s32":
			old = _patched.decode_s32(at)
			_patched.encode_s32(at, row.value)
		"u32":
			old = _patched.decode_u32(at)
			_patched.encode_u32(at, row.value)
		"s16":
			old = _patched.decode_s16(at)
			_patched.encode_s16(at, row.value)
		"u16":
			old = _patched.decode_u16(at)
			_patched.encode_u16(at, row.value)
		"u8":
			old = _patched.decode_u8(at)
			_patched.encode_u8(at, row.value)
	edits.append(PackedStringArray([row.kind, row.target, row.subject, row.field, resource, "0x%X" % at, str(old), str(row.value)]))
	return ""
