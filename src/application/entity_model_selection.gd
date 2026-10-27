class_name EntityModelSelection
extends RefCounted
## Resolves behavior-selected models through player-owned map-book and archive data.

const SWITCH_WAD_SLOTS: PackedInt32Array = [11, 0, 1, 2, 3, 4, 5, 6, 7]

## Selects the frozen colour-switch WAD slot or the supplied form's ordinary model.
static func resource_for(data: GameData, level: int, form: FormBookEntry, entity: EntityDefinition, low_poly: bool = false) -> int:
	if data == null or form == null or entity == null:
		return -1
	if entity.behavior.kind == EntityBehavior.Kind.VOL_COLOUR_SWITCH:
		if entity.volcano == null or entity.volcano.colour < 0 or entity.volcano.colour >= SWITCH_WAD_SLOTS.size():
			return -1
		var row: MapBookEntry = data.map_book_entry(level)
		return data.model_resource_at(row.wad_id(low_poly), SWITCH_WAD_SLOTS[entity.volcano.colour]) if row != null else -1
	return data.model_resource_at(data.model_wad_for(form, level, low_poly), form.wad_index()) if form.model_id >= 0 else -1
