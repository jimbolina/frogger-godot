class_name GameNameLists
extends RefCounted
## The FrogLord name lists one build uses, loaded together.
##
## Tables in the executable are numbered lists without names; FrogLord's
## configuration names their entries. Some tables also take their [i]length[/i]
## from these lists, exactly as FrogLord does: the form libraries (one list
## section per theme) and the script table (the main script list).

## Form names, all themes in theme order; each theme is also a sub-bank named
## after it (e.g. "SWAMP").
var forms: NameBank
## Entity type names.
var entities: NameBank
## Entity script names (the main list; callbacks are the "CallbackNames" sub-bank).
var scripts: NameBank
## Sound effect names, or null if the build names none.
var sounds: NameBank
## Texture names by texture id, or null if the build names none.
var images: NameBank
## Animation names, or null if the build names none.
var anims: NameBank
## Form name to entity type name, from the entity list's [code][Override][/code]
## section: forms whose stored entity type FrogLord displays differently.
var entity_overrides: Dictionary[String, String] = {}
## Problems met while loading; empty when every list loaded.
var errors: PackedStringArray = PackedStringArray()


## Loads the lists [param version] names from [param library].
static func load_for(version: GameVersionConfig, library: FrogLordConfigLibrary) -> GameNameLists:
	var lists := GameNameLists.new()
	lists.forms = lists._bank(library, "forms", version.form_list)
	lists.entities = lists._bank(library, "entities", version.entity_list)
	lists.scripts = lists._bank(library, "scripts", version.script_list)
	if not version.sound_list.is_empty():
		lists.sounds = lists._bank(library, "sounds", version.sound_list)
	if not version.anim_list.is_empty():
		lists.anims = lists._bank(library, "anims", version.anim_list)
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


## The entity type name FrogLord shows for form [param form_name] whose stored
## entity type is [param entity_type]: the override when one exists and names
## a known entity, else the list entry (or "" when unnamed).
func entity_name_for(form_name: String, entity_type: int) -> String:
	if entity_overrides.has(form_name):
		var replacement: int = entities.index_of(entity_overrides[form_name])
		if replacement >= 0:
			return entities.get_name(replacement)
	return entities.get_name(entity_type) if entities.has_name(entity_type) else ""


func _bank(library: FrogLordConfigLibrary, folder: String, list_name: String) -> NameBank:
	var bank: NameBank = library.load_name_bank(folder, list_name)
	if bank == null:
		errors.append(library.error)
		bank = NameBank.new()
	return bank
