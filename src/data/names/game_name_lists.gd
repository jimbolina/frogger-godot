class_name GameNameLists
extends Resource
## The FrogLord name lists one build uses, loaded together.
##
## Tables in the executable are numbered lists without names; FrogLord's
## configuration names their entries. Some tables also take their [i]length[/i]
## from these lists, exactly as FrogLord does: the form libraries (one list
## section per theme) and the script table (the main script list).
## [GameNameListsReader] loads them from FrogLord's files.

## Form names, all themes in theme order; each theme is also a sub-bank named
## after it (e.g. "SWAMP").
@export var forms: NameBank
## Entity type names.
@export var entities: NameBank
## Entity script names (the main list; callbacks are the "CallbackNames" sub-bank).
@export var scripts: NameBank
## Sound effect names, or null if the build names none.
@export var sounds: NameBank
## Texture names by texture id, or null if the build names none.
@export var images: NameBank
## Animation names, or null if the build names none.
@export var anims: NameBank
## Form name to entity type name, from the entity list's [code][Override][/code]
## section: forms whose stored entity type FrogLord displays differently.
@export var entity_overrides: Dictionary[String, String] = {}
## Problems met while loading; empty when every list loaded.
@export var errors: PackedStringArray = PackedStringArray()


## The entity type name FrogLord shows for form [param form_name] whose stored
## entity type is [param entity_type]: the override when one exists and names
## a known entity, else the list entry (or "" when unnamed).
func entity_name_for(form_name: String, entity_type: int) -> String:
	if entity_overrides.has(form_name):
		var replacement: int = entities.index_of(entity_overrides[form_name])
		if replacement >= 0:
			return entities.name_of(replacement)
	return entities.name_of(entity_type) if entities.has_name(entity_type) else ""
