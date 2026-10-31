class_name SyntheticExe
extends RefCounted
## Builds small fake executables for testing the table readers without game files.
##
## The buffer starts with "MZ" (so FrogLord's trailer check accepts it) and
## is zero elsewhere; tests write the tables they need at chosen offsets and
## set the matching addresses on [member version]. Addresses stored inside
## tables use [constant RAM_OFFSET], like a real Windows program.

## Added to a file offset to get the in-program address.
const RAM_OFFSET: int = 0x400000

## The bytes being built.
var bytes := PackedByteArray()
## A build description pointing at the tables (all addresses unset at first).
var version := GameVersionConfig.new()


## An executable of [param size] zero bytes (plus the MZ signature).
func _init(size: int = 0x2000) -> void:
	bytes.resize(size)
	bytes[0] = 0x4D
	bytes[1] = 0x5A
	version.internal_name = "synthetic"
	version.display_name = "Synthetic test build"
	version.platform = "WINDOWS"
	version.ram_offset = RAM_OFFSET


## The in-program address of file offset [param offset].
static func ptr(offset: int) -> int:
	return offset + RAM_OFFSET


## Writes a signed 32-bit value.
func s32(offset: int, value: int) -> void:
	bytes.encode_s32(offset, value)


## Writes an unsigned 32-bit value.
func u32(offset: int, value: int) -> void:
	bytes.encode_u32(offset, value & 0xFFFFFFFF)


## Writes several 32-bit values in a row; returns the offset after them.
func s32s(offset: int, values: Array[int]) -> int:
	for i: int in values.size():
		bytes.encode_u32(offset + 4 * i, values[i] & 0xFFFFFFFF)
	return offset + 4 * values.size()


## Writes 16-bit values in a row; returns the offset after them.
func s16s(offset: int, values: Array[int]) -> int:
	for i: int in values.size():
		bytes.encode_s16(offset + 2 * i, values[i])
	return offset + 2 * values.size()


## Writes bytes; returns the offset after them.
func put(offset: int, data: PackedByteArray) -> int:
	for i: int in data.size():
		bytes[offset + i] = data[i]
	return offset + data.size()


## Writes an archive index at [param offset] listing [param files] as
## [path, type id, flags] triples (resource id = position) and points
## [member version] at it.
func add_mwi(offset: int, files: Array[Array]) -> void:
	var names := PackedByteArray()
	var table_size: int = files.size() * MwiEntry.ENTRY_SIZE
	var name_offsets: Array[int] = []
	for f: Array in files:
		var path: String = f[0]
		name_offsets.append(table_size + names.size())
		names.append_array(path.to_ascii_buffer())
		names.append(0)
		while names.size() % 4 != 0:
			names.append(0)
	for i: int in files.size():
		var f: Array = files[i]
		var type_id: int = f[1]
		var flags: int = f[2]
		s32s(offset + i * MwiEntry.ENTRY_SIZE, [name_offsets[i], flags, type_id, i + 1, 0, 0, 16, 16])
	put(offset + table_size, names)
	version.mwi_offset = offset
	version.mwi_length = table_size + names.size()


## The executable as an [ExeImage].
func image() -> ExeImage:
	return ExeImage.create(bytes, version)


## The archive index written by [method add_mwi].
func mwi() -> MwiIndex:
	return MwiIndexReader.from_exe(bytes, version)


## The executable with FrogLord's build information appended, carrying
## [param root_keys] (e.g. demoTableAddress) beside a BuildInfo section.
func with_trailer(root_keys: String) -> PackedByteArray:
	var text: String = root_keys + "[BuildInfo]\ngameType=frogger\ngameVersion=pc-retail-v3.0e\nfrogLordVersion=1\n"
	var out: PackedByteArray = bytes.duplicate()
	out.append_array(FrogLordExeTrailer.build_footer(text, bytes.size()))
	return out


## Name lists for tests: form sections and entity names from config text.
static func name_lists(forms_cfg: String, entities_cfg: String, scripts_cfg: String = "SCRIPT_NONE\n") -> GameNameLists:
	var lists := GameNameLists.new()
	lists.forms = NameBankReader.from_list_config(FrogLordConfig.parse_legacy(forms_cfg), true, "Form")
	var entity_config: FrogLordConfig = FrogLordConfig.parse_legacy(entities_cfg)
	lists.entities = NameBankReader.from_list_config(entity_config, true, "Entity")
	var overrides: FrogLordConfig = entity_config.get_child("Override")
	if overrides != null:
		for key: String in overrides.keys():
			lists.entity_overrides[key] = overrides.get_string(key)
	lists.scripts = NameBankReader.from_list_config(FrogLordConfig.parse_legacy(scripts_cfg), false, "Script")
	return lists
