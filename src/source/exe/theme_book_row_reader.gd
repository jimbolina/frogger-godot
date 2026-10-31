class_name ThemeBookRowReader
extends RefCounted
## Reads single theme book rows and forms; [ThemeBookReader] names them and
## sizes the form libraries.


## Reads one theme row ([ThemeBookEntry], 40 bytes) at [param reader]'s cursor.
static func read_entry(reader: ByteReader, theme_number: int) -> ThemeBookEntry:
	var t := ThemeBookEntry.new()
	t.theme = theme_number
	t.high_wad_id = reader.read_s32()
	t.form_library_pointer = reader.read_u32()
	t.high_vlo_id = reader.read_s32()
	t.death_height = reader.read_s32()
	t.high_multiplayer_wad_id = reader.read_s32()
	t.high_multiplayer_vlo_id = reader.read_s32()
	t.low_wad_id = reader.read_s32()
	t.low_vlo_id = reader.read_s32()
	t.low_multiplayer_wad_id = reader.read_s32()
	t.low_multiplayer_vlo_id = reader.read_s32()
	return t


## Reads one form ([FormBookEntry], 32 bytes) at [param reader]'s cursor.
static func read_form(reader: ByteReader, theme_number: int, local: int, global: int) -> FormBookEntry:
	var f := FormBookEntry.new()
	f.theme = theme_number
	f.local_id = local
	f.global_id = global
	f.entity_type = reader.read_s32()
	f.model_id = reader.read_s32()
	f.script_id = reader.read_s32()
	f.flags = reader.read_s32()
	f.collision_callback = reader.read_u32()
	f.radius_squared = reader.read_s32()
	f.death_type = reader.read_s32()
	f.bonus_callback = reader.read_u32()
	return f
