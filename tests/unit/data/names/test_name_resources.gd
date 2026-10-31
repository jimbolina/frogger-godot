extends GutTest
## NameBank and GameNameLists survive a resource save and load with their lookups intact.

const ROOT: String = "user://test_name_resources"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)


func after_all() -> void:
	for file: String in DirAccess.get_files_at(ROOT):
		DirAccess.remove_absolute(ROOT.path_join(file))
	DirAccess.remove_absolute(ROOT)


func _round_trip(resource: Resource, file_name: String) -> Resource:
	var path: String = ROOT.path_join(file_name)
	assert_eq(ResourceSaver.save(resource, path), OK, file_name)
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)


func _list_bank() -> NameBank:
	var config: FrogLordConfig = FrogLordConfig.parse_legacy("SCRIPT_NONE\nSCRIPT_TURTLE\n[CallbackNames]\nSCRIPT_CB_HIT_TURTLE\n")
	return NameBankReader.from_list_config(config, false, "Script")


func _image_bank() -> NameBank:
	return NameBankReader.from_indexed_config(FrogLordConfig.parse_legacy("12=for_swarm\n40=fire_fly\n"), "Image")


func test_list_bank_round_trip_keeps_names_and_sections() -> void:
	var loaded := _round_trip(_list_bank(), "scripts.tres") as NameBank
	assert_not_null(loaded)
	assert_eq(loaded.size(), 2)
	assert_eq(loaded.name_of(1), "SCRIPT_TURTLE")
	assert_eq(loaded.name_of(5), "Unknown Script [5]")
	assert_eq(loaded.index_of("script_turtle"), 1)
	assert_eq(loaded.sub_bank_names(), PackedStringArray(["CallbackNames"]))
	assert_eq(loaded.get_sub_bank("CallbackNames").name_of(0), "SCRIPT_CB_HIT_TURTLE")


func test_indexed_bank_round_trip_keeps_ids() -> void:
	var loaded := _round_trip(_image_bank(), "images.tres") as NameBank
	assert_not_null(loaded)
	assert_eq(loaded.size(), 2)
	assert_true(loaded.has_name(40))
	assert_false(loaded.has_name(0))
	assert_eq(loaded.name_of(12), "for_swarm")
	assert_eq(loaded.index_of("FIRE_FLY"), 40)
	assert_eq(loaded.name_of(3), "Unknown Image [3]")


func test_lists_round_trip_keeps_banks_overrides_and_errors() -> void:
	var lists := GameNameLists.new()
	lists.entities = NameBankReader.from_list_config(FrogLordConfig.parse_legacy("STATIC\nMOVING\n"), true, "Entity")
	lists.scripts = _list_bank()
	lists.images = _image_bank()
	lists.entity_overrides["SUB_TURTLE"] = "MOVING"
	lists.errors.append("anims: missing")
	var loaded := _round_trip(lists, "lists.tres") as GameNameLists
	assert_not_null(loaded)
	assert_null(loaded.sounds)
	assert_eq(loaded.scripts.get_sub_bank("CallbackNames").size(), 1)
	assert_eq(loaded.images.name_of(40), "fire_fly")
	assert_eq(loaded.entity_name_for("SUB_TURTLE", 0), "MOVING")
	assert_eq(loaded.entity_name_for("SUB_LOG", 0), "STATIC")
	assert_eq(loaded.errors, PackedStringArray(["anims: missing"]))
