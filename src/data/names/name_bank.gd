class_name NameBank
extends Resource
## An index-to-name list from FrogLord, e.g. sound effect or entity names.
##
## The original game refers to most things by number: sound 12, form 40,
## entity type 7. FrogLord's name lists give those numbers their official or
## community names. A list file has its names as text lines, optionally split
## into sections ([code][GENERIC][/code], [code][CAVES][/code], ...). For most
## lists the sections are one numbering continued across sections; each
## section is also available on its own as a sub-bank.
##
## Texture names use a different shape ([code]id=name[/code] pairs, not a
## list) and fill [member names_by_id] instead of [member names].

## Names in index order.
@export var names: PackedStringArray = PackedStringArray()
## Label for unnamed indices, e.g. "Sound" gives "Unknown Sound [12]".
@export var unknown_label: String = ""
## Each section of the list as its own bank, by section name.
@export var sub_banks: Dictionary[String, NameBank] = {}
## Names by id for an indexed bank ([code]id=name[/code] pairs); empty for a list.
@export var names_by_id: Dictionary[int, String] = {}


## Number of names in the main list (for an indexed bank, the number of pairs).
func size() -> int:
	return names.size() if names_by_id.is_empty() else names_by_id.size()


## True if [param index] has a real name.
func has_name(index: int) -> bool:
	if not names_by_id.is_empty():
		return names_by_id.has(index)
	return index >= 0 and index < names.size()


## The name of [param index], or a placeholder such as "Unknown Sound [12]".
func name_of(index: int) -> String:
	if not names_by_id.is_empty():
		if names_by_id.has(index):
			return names_by_id[index]
	elif index >= 0 and index < names.size():
		return names[index]
	return "Unknown %s [%d]" % [unknown_label, index]


## The index of [param entry_name] (case-insensitive), or -1.
func index_of(entry_name: String) -> int:
	var wanted: String = entry_name.to_lower()
	if not names_by_id.is_empty():
		for id: int in names_by_id:
			if names_by_id[id].to_lower() == wanted:
				return id
		return -1
	for i: int in names.size():
		if names[i].to_lower() == wanted:
			return i
	return -1


## The section called [param section_name] as its own bank, or null.
func get_sub_bank(section_name: String) -> NameBank:
	if not sub_banks.has(section_name):
		return null
	return sub_banks[section_name]


## Names of the sections in this bank.
func sub_bank_names() -> PackedStringArray:
	return PackedStringArray(sub_banks.keys())
