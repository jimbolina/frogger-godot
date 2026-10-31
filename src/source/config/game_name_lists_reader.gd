class_name GameNameListsReader
extends RefCounted
## Loads the [GameNameLists] of one build from FrogLord's configuration files.


## Loads the lists [param version] names from [param library].
static func load_for(version: GameVersionConfig, library: FrogLordConfigLibrary) -> GameNameLists:
	var lists := GameNameLists.new()
	lists.forms = _bank(lists, library, "forms", version.form_list)
	lists.entities = _bank(lists, library, "entities", version.entity_list)
	lists.scripts = _bank(lists, library, "scripts", version.script_list)
	if not version.sound_list.is_empty():
		lists.sounds = _bank(lists, library, "sounds", version.sound_list)
	if not version.anim_list.is_empty():
		lists.anims = _bank(lists, library, "anims", version.anim_list)
	if not version.image_list.is_empty():
		lists.images = library.load_image_names(version.image_list)
		if lists.images == null:
			lists.errors.append(library.error)
	var entity_config: FrogLordConfig = library.load_config("entities", version.entity_list)
	var overrides: FrogLordConfig = entity_config.get_child("Override") if entity_config != null else null
	if overrides != null:
		for key: String in overrides.keys():
			lists.entity_overrides[key] = overrides.get_string(key)
	return lists


static func _bank(lists: GameNameLists, library: FrogLordConfigLibrary, folder: String, list_name: String) -> NameBank:
	var bank: NameBank = library.load_name_bank(folder, list_name)
	if bank == null:
		lists.errors.append(library.error)
		bank = NameBank.new()
	return bank
