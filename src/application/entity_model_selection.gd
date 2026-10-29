class_name EntityModelSelection
extends RefCounted
## Resolves behavior-selected models through player-owned map-book and archive data.

const SWITCH_WAD_SLOTS: PackedInt32Array = [11, 0, 1, 2, 3, 4, 5, 6, 7]
## Source jun_plinth_table: plinth 0 uses 50 + JUNGLE_WAD_OFFSET, the others the top of the map WAD.
const PLINTH_WAD_SLOTS: PackedInt32Array = [58, 0, 1, 2, 3, 4, 5, 6, 7]
## Source DES_FALL_ROCKROLL map WAD slot shared by falling and rolling rock explosions.
const EXPLOSION_WAD_SLOT: int = 1

## Selects the frozen colour-switch or plinth WAD slot, or the supplied form's ordinary model.
static func resource_for(data: GameData, level: int, form: FormBookEntry, entity: EntityDefinition, low_poly: bool = false) -> int:
	if data == null or form == null or entity == null:
		return -1
	if entity.behavior.kind == EntityBehavior.Kind.VOL_COLOUR_SWITCH:
		if entity.volcano == null or entity.volcano.colour < 0 or entity.volcano.colour >= SWITCH_WAD_SLOTS.size():
			return -1
		return _level_wad_model(data, level, SWITCH_WAD_SLOTS[entity.volcano.colour], low_poly)
	if entity.behavior.kind == EntityBehavior.Kind.JUN_PLINTH:
		if entity.jungle == null or entity.jungle.op_id < 0 or entity.jungle.op_id >= PLINTH_WAD_SLOTS.size():
			return -1
		return _level_wad_model(data, level, PLINTH_WAD_SLOTS[entity.jungle.op_id], low_poly)
	return data.model_resource_at(data.model_wad_for(form, level, low_poly), form.wad_index()) if form.model_id >= 0 else -1

## Selects the level WAD's frozen DES_FALL_ROCKROLL slot-1 rock explosion model, or -1.
static func explosion_resource_for(data: GameData, level: int, low_poly: bool = false) -> int:
	if data == null:
		return -1
	return _level_wad_model(data, level, EXPLOSION_WAD_SLOT, low_poly)

static func _level_wad_model(data: GameData, level: int, slot: int, low_poly: bool) -> int:
	var row: MapBookEntry = data.map_book_entry(level)
	return data.model_resource_at(row.wad_id(low_poly), slot) if row != null else -1
