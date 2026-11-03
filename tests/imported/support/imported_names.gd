class_name ImportedNames
extends RefCounted
## Helpers for the frozen-fact tests that need the imported FrogLord name
## lists: the lists themselves, the JSON facts read as integers, and
## supplied-table stand-ins holding frozen-source programs under their
## FrogLord ids.

## The imported FrogLord name lists of the retail build.
const NAMES: String = "res://assets/tables/names.tres"
## The opcode that stops a script, used to fill programs the facts omit.
const STOP_OPCODE: int = 38


## The imported name lists, or null when they do not load.
static func lists() -> GameNameLists:
	return load(NAMES) as GameNameLists


## The JSON document at [param path].
static func facts(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## A JSON number as an integer.
static func number(value: Variant) -> int:
	var parsed: float = value
	return int(parsed)


## A JSON array of numbers as integers.
static func numbers(values: Variant) -> Array[int]:
	var source: Array = values
	var result: Array[int] = []
	for value: Variant in source:
		result.append(number(value))
	return result


## A JSON array of three numbers as a vector.
static func vector(values: Variant) -> Vector3i:
	var items: Array[int] = numbers(values)
	return Vector3i(items[0], items[1], items[2])


## A table holding [param programs] (instruction words by FrogLord id, as
## strings) under their names in [param bank], and a stop instruction for
## every lower id the facts omit.
static func table(bank: NameBank, programs: Dictionary) -> ScriptTable:
	var result := ScriptTable.new()
	var highest: int = 0
	for key: String in programs:
		highest = maxi(highest, key.to_int())
	for id: int in range(highest + 1):
		var program := EntityScript.new()
		program.id = id
		program.name = bank.name_of(id)
		var words: Array[int] = [STOP_OPCODE]
		if programs.has(str(id)):
			words = numbers(programs[str(id)])
		var cursor: int = 0
		while cursor < words.size():
			var command := EntityScript.Command.new()
			command.opcode = words[cursor]
			var width: int = EntityScriptDefinition.WIDTHS[command.opcode]
			command.arguments = PackedInt32Array(words.slice(cursor + 1, cursor + width))
			program.commands.append(command)
			cursor += width
		result.scripts.append(program)
	return result
