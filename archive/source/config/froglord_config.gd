class_name FrogLordConfig
extends RefCounted
## One section of a FrogLord configuration file, with its child sections.
##
## FrogLord (the Frogger modding toolkit) describes each game build and its
## name lists in plain-text [code].cfg[/code] files. A section holds
## [code]key=value[/code] pairs, free "text" lines (lists of names), and
## nested child sections written as [code][Name][/code], [code][[Child]][/code]
## and so on.
##
## FrogLord has two readers for this format. Its game version files and name
## lists go through the older one ([LegacyConfigParser]); the build
## information FrogLord embeds in a modded executable goes through the newer
## one ([ModernConfigParser]). Both produce this same tree.

## Section name ([code]""[/code] or the file name for the root).
var name: String = ""
## The comment written after a section header (newer format only).
var comment: String = ""
## Nesting depth: 0 for the root, 1 for [code][Section][/code], and so on.
var layer: int = 0
## Free text lines in file order.
var text: PackedStringArray = PackedStringArray()
## Child sections in file order (duplicates kept, as FrogLord keeps them).
var children: Array[FrogLordConfig] = []

var _values: Dictionary[String, Variant] = {}
var _children_by_name: Dictionary[String, FrogLordConfig] = {}


## Creates an empty section called [param section_name] at depth [param depth].
func _init(section_name: String = "", depth: int = 0) -> void:
	name = section_name
	layer = depth


## Parses [param source] with the older reader FrogLord uses for version files
## and name lists. Returns null on a syntax error; see [LegacyConfigParser].
static func parse_legacy(source: String, root_name: String = "") -> FrogLordConfig:
	return LegacyConfigParser.new().parse(source, root_name)


## Parses [param source] with FrogLord's newer reader (escapes, section
## comments, strict duplicate checks). Returns null on a syntax error.
static func parse_modern(source: String, root_name: String = "") -> FrogLordConfig:
	return ModernConfigParser.new().parse(source, root_name)


## Stores [param value] under [param key]. A null value is the newer format's
## literal [code]null[/code].
func set_value(key: String, value: Variant) -> void:
	_values[key] = value


## Adds [param child] after the existing children. A later child with the
## same name shadows an earlier one for [method get_child], as in FrogLord.
func add_child(child: FrogLordConfig) -> void:
	children.append(child)
	_children_by_name[child.name] = child


## True if [param key] has a value in this section (child sections not searched).
func has_key(key: String) -> bool:
	return _values.has(key)


## Keys of this section in the order they first appeared.
func keys() -> PackedStringArray:
	return PackedStringArray(_values.keys())


## The raw text of [param key], or [param fallback] when it is absent or null.
func get_string(key: String, fallback: String = "") -> String:
	var value: Variant = _values.get(key)
	if value is String:
		var text_value: String = value
		return text_value
	return fallback


## Reads [param key] as an integer using Java's [code]Integer.decode[/code]
## rules (see [method decode_integer]); returns [param fallback] if absent or
## malformed. Use [method has_valid_int] to tell the two apart.
func get_int(key: String, fallback: int = 0) -> int:
	if not has_key(key):
		return fallback
	var parsed: Variant = decode_integer(get_string(key))
	if parsed is int:
		var number: int = parsed
		return number
	return fallback


## True if [param key] is present and decodes as an integer.
func has_valid_int(key: String) -> bool:
	return has_key(key) and decode_integer(get_string(key)) is int


## Reads [param key] as a boolean: true only for "true" in any letter case.
func get_bool(key: String, fallback: bool = false) -> bool:
	if not has_key(key):
		return fallback
	return get_string(key).to_lower() == "true"


## Reads a comma-separated list of decimal integers. Returns an empty array
## if the key is absent or any element is malformed.
func get_int_array(key: String) -> PackedInt64Array:
	var result := PackedInt64Array()
	if not has_key(key):
		return result
	for part: String in get_string(key).split(","):
		var parsed: Variant = decode_integer(part.strip_edges())
		if not parsed is int:
			return PackedInt64Array()
		var number: int = parsed
		result.append(number)
	return result


## True if a child section called [param child_name] exists.
func has_child(child_name: String) -> bool:
	return _children_by_name.has(child_name)


## The child section called [param child_name], or null.
func get_child(child_name: String) -> FrogLordConfig:
	if not _children_by_name.has(child_name):
		return null
	return _children_by_name[child_name]


## Decodes an integer the way Java's [code]Integer.decode[/code] / [code]Long.decode[/code]
## do, which is how FrogLord reads numbers: optional sign, then [code]0x[/code],
## [code]0X[/code] or [code]#[/code] for hexadecimal, a leading [code]0[/code] for octal,
## otherwise decimal. Returns null when the text is not a number.
static func decode_integer(source: String) -> Variant:
	var s: String = source
	if s.is_empty():
		return null
	var negative: bool = false
	if s[0] == "-" or s[0] == "+":
		negative = s[0] == "-"
		s = s.substr(1)
	var radix: int = 10
	if s.begins_with("0x") or s.begins_with("0X"):
		radix = 16
		s = s.substr(2)
	elif s.begins_with("#"):
		radix = 16
		s = s.substr(1)
	elif s.begins_with("0") and s.length() > 1:
		radix = 8
		s = s.substr(1)
	if s.is_empty() or s[0] == "-" or s[0] == "+":
		return null
	var value: int = 0
	for ch: String in s:
		var digit: int = "0123456789abcdef".find(ch.to_lower())
		if digit < 0 or digit >= radix:
			return null
		if value > (0x7FFFFFFFFFFFFFFF - digit) / radix:
			return null
		value = value * radix + digit
	return -value if negative else value
