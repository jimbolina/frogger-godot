class_name ViewerArguments
extends RefCounted
## Shared tool arguments. Callers supply user arguments, keeping tests independent of OS state.


## Value following the first argument starting with [param prefix], including an empty value.
static func value(arguments: PackedStringArray, prefix: String) -> String:
	for argument: String in arguments:
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
	return ""


## Whether an argument starts with [param prefix], including one with an empty value.
static func has_prefix(arguments: PackedStringArray, prefix: String) -> bool:
	for argument: String in arguments:
		if argument.begins_with(prefix):
			return true
	return false


## Whether [param flag] appears exactly, without treating a value argument as a flag.
static func has_flag(arguments: PackedStringArray, flag: String) -> bool:
	return arguments.has(flag)


## Locates data using the first explicit folder, then the locator's environment/saved precedence.
static func locate_data(arguments: PackedStringArray) -> GameDataLocator.Located:
	return GameDataLocator.new().locate(value(arguments, "--data-dir="))
