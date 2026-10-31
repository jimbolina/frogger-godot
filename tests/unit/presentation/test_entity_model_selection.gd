extends GutTest
## Colour-selected models follow player map-book WADs without fixed resource IDs.

class SelectedData extends AssetCatalog:
	var selected_row := MapBookEntry.new()
	var requested_wad: int = -1
	var requested_slot: int = -1

	func map_book_entry(_level: int) -> MapBookEntry:
		return selected_row

	func model_resource_at(wad_resource_id: int, position: int) -> int:
		requested_wad = wad_resource_id
		requested_slot = position
		return 10000 + wad_resource_id + position

func test_switch_colour_selects_each_source_slot_in_supplied_detail_wad() -> void:
	var data := SelectedData.new()
	data.selected_row.high_wad_id = 321
	data.selected_row.low_wad_id = 654
	var form := FormBookEntry.new()
	form.model_id = 99
	var entity := EntityDefinition.new()
	entity.behavior = EntityBehaviorCatalog.resolve("VOL_COLOUR_SWITCH")
	entity.volcano = EntityVolcanoDefinition.new()
	for low_poly: bool in [false, true]:
		for colour: int in 9:
			entity.volcano.colour = colour
			var slot: int = 11 if colour == 0 else colour - 1
			var wad: int = 654 if low_poly else 321
			assert_eq(EntityModelSelection.resource_for(data, 54, form, entity, low_poly), 10000 + wad + slot)
			assert_eq(data.requested_wad, wad)
			assert_eq(data.requested_slot, slot)
	entity.volcano.colour = 9
	assert_eq(EntityModelSelection.resource_for(data, 54, form, entity), -1)

func test_plinth_id_selects_the_source_plinth_table_slot_in_supplied_detail_wad() -> void:
	var data := SelectedData.new()
	data.selected_row.high_wad_id = 305
	data.selected_row.low_wad_id = 405
	var form := FormBookEntry.new()
	form.model_id = 58
	var entity := EntityDefinition.new()
	entity.behavior = EntityBehaviorCatalog.resolve("JUN_PLINTH")
	assert_eq(EntityModelSelection.resource_for(data, 54, form, entity), -1)
	entity.jungle = EntityJungleDefinition.new()
	for low_poly: bool in [false, true]:
		for op_id: int in 9:
			entity.jungle.op_id = op_id
			var slot: int = 58 if op_id == 0 else op_id - 1
			var wad: int = 405 if low_poly else 305
			assert_eq(EntityModelSelection.resource_for(data, 54, form, entity, low_poly), 10000 + wad + slot)
			assert_eq(data.requested_slot, slot)
	for op_id: int in [-1, 9]:
		entity.jungle.op_id = op_id
		assert_eq(EntityModelSelection.resource_for(data, 54, form, entity), -1)
