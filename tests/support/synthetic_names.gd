class_name SyntheticNames
extends RefCounted
## Builds small [NameBank]s for tests from text written like FrogLord's name
## lists: one name per line, [code][Section][/code] lines opening sections,
## and [code]id=name[/code] lines for the texture names.


## A list bank of the lines of [param text]. Each section becomes a sub-bank;
## with [param sections_extend_main] its names are also appended to the main
## list, as FrogLord does for every list but the script names.
static func list(text: String, sections_extend_main: bool, label: String) -> NameBank:
	var bank := NameBank.new()
	bank.unknown_label = label
	var section: NameBank = null
	for line: String in _lines(text):
		if line.begins_with("[") and line.ends_with("]"):
			section = NameBank.new()
			section.unknown_label = label
			bank.sub_banks[line.substr(1, line.length() - 2)] = section
			continue
		if section == null:
			bank.names.append(line)
			continue
		section.names.append(line)
		if sections_extend_main:
			bank.names.append(line)
	return bank


## An indexed bank of the [code]id=name[/code] lines of [param text]; lines
## whose id is not an integer are ignored.
static func indexed(text: String, label: String) -> NameBank:
	var bank := NameBank.new()
	bank.unknown_label = label
	for line: String in _lines(text):
		var equals_at: int = line.find("=")
		if equals_at < 0 or not line.substr(0, equals_at).is_valid_int():
			continue
		bank.names_by_id[line.substr(0, equals_at).to_int()] = line.substr(equals_at + 1)
	return bank


static func _lines(text: String) -> PackedStringArray:
	var kept := PackedStringArray()
	for line: String in text.split("\n"):
		var clean: String = line.rstrip(" \t\r")
		if not clean.is_empty():
			kept.append(clean)
	return kept
