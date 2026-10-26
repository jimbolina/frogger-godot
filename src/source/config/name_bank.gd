class_name NameBank
extends RefCounted
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
## list); [method from_indexed_config] reads those.

## Names in index order.
var names: PackedStringArray = PackedStringArray()
## Label for unnamed indices, e.g. "Sound" gives "Unknown Sound [12]".
var unknown_label: String = ""

var _sub_banks: Dictionary[String, NameBank] = {}
var _names_by_id: Dictionary[int, String] = {}


## Builds a bank from a list-style config. When [param children_extend_main]
## is true (sounds, forms, entities, animations) the sections' names are
## appended to the main list in file order; when false (scripts) the sections
## stay separate and are reachable only through [method get_sub_bank].
static func from_list_config(config: FrogLordConfig, children_extend_main: bool, label: String) -> NameBank:
	var bank := NameBank.new()
	bank.unknown_label = label
	bank.names.append_array(config.text)
	for child: FrogLordConfig in config.children:
		var sub := NameBank.new()
		sub.unknown_label = label
		sub.names.append_array(child.text)
		bank._sub_banks[child.name] = sub
		if children_extend_main:
			bank.names.append_array(child.text)
	return bank


## Builds a bank from [code]id=name[/code] pairs (the texture name lists).
## Keys that are not integers are ignored, as FrogLord ignores them.
static func from_indexed_config(config: FrogLordConfig, label: String) -> NameBank:
	var bank := NameBank.new()
	bank.unknown_label = label
	for key: String in config.keys():
		if not key.is_valid_int():
			continue
		bank._names_by_id[key.to_int()] = config.get_string(key)
	return bank


## Number of names in the main list (for an indexed bank, the number of pairs).
func size() -> int:
	return names.size() if _names_by_id.is_empty() else _names_by_id.size()


## True if [param index] has a real name.
func has_name(index: int) -> bool:
	if not _names_by_id.is_empty():
		return _names_by_id.has(index)
	return index >= 0 and index < names.size()


## The name of [param index], or a placeholder such as "Unknown Sound [12]".
func get_name(index: int) -> String:
	if not _names_by_id.is_empty():
		if _names_by_id.has(index):
			return _names_by_id[index]
	elif index >= 0 and index < names.size():
		return names[index]
	return "Unknown %s [%d]" % [unknown_label, index]


## The index of [param entry_name] (case-insensitive), or -1.
func index_of(entry_name: String) -> int:
	var wanted: String = entry_name.to_lower()
	if not _names_by_id.is_empty():
		for id: int in _names_by_id:
			if _names_by_id[id].to_lower() == wanted:
				return id
		return -1
	for i: int in names.size():
		if names[i].to_lower() == wanted:
			return i
	return -1


## The section called [param section_name] as its own bank, or null.
func get_sub_bank(section_name: String) -> NameBank:
	if not _sub_banks.has(section_name):
		return null
	return _sub_banks[section_name]


## Names of the sections in this bank.
func sub_bank_names() -> PackedStringArray:
	return PackedStringArray(_sub_banks.keys())
