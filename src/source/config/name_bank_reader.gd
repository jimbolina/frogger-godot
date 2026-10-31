class_name NameBankReader
extends RefCounted
## Builds [NameBank]s from FrogLord's parsed list files.


## Builds a bank from a list-style config. When [param children_extend_main]
## is true (sounds, forms, entities, animations) the sections' names are
## appended to the main list in file order; when false (scripts) the sections
## stay separate and are reachable only through [method NameBank.get_sub_bank].
static func from_list_config(config: FrogLordConfig, children_extend_main: bool, label: String) -> NameBank:
	var bank := NameBank.new()
	bank.unknown_label = label
	bank.names.append_array(config.text)
	for child: FrogLordConfig in config.children:
		var sub := NameBank.new()
		sub.unknown_label = label
		sub.names.append_array(child.text)
		bank.sub_banks[child.name] = sub
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
		bank.names_by_id[key.to_int()] = config.get_string(key)
	return bank
