class_name ModernConfigParser
extends RefCounted
## Reads FrogLord's newer configuration dialect.
##
## FrogLord writes this dialect into the build information it appends to a
## modded executable (see [FrogLordExeTrailer]). The rules follow FrogLord's
## [code]system/Config.java[/code]:
## [br]- Lines are trimmed at both ends.
## [br]- [code]#[/code] starts a comment; [code]##[/code] is an escaped, literal [code]#[/code].
## [br]- [code][Name][/code] with an optional trailing comment opens a section. A
##   section may be at most one level deeper than its parent; a shallower or
##   equal header closes the current section and belongs to an ancestor.
## [br]- [code]key=value[/code] is a pair when no space appears before the first
##   unescaped [code]=[/code]; [code]\\[/code] escapes the next key character.
##   The value [code]null[/code] means no value; [code]"null"[/code] is the text "null".
## [br]- A key may appear only once per section.
## [br]- Every other line, including blank ones, is a text line.

## Why the last parse failed, or an empty string after a successful parse.
var error: String = ""

var _lines: PackedStringArray
var _next: int = 0


## Parses [param source] into a tree rooted at [param root_name]. Returns null
## and sets [member error] on a syntax error.
func parse(source: String, root_name: String = "") -> FrogLordConfig:
	error = ""
	_lines = source.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	if _lines.size() > 0 and _lines[_lines.size() - 1].is_empty():
		_lines.resize(_lines.size() - 1) # A final newline ends the last line; it does not start another.
	_next = 0
	var root: FrogLordConfig = _read_section(0, root_name, "")
	return null if not error.is_empty() else root


func _read_section(layer: int, section_name: String, section_comment: String) -> FrogLordConfig:
	var config := FrogLordConfig.new(section_name, layer)
	config.comment = section_comment
	while _next < _lines.size() and error.is_empty():
		var line_number: int = _next + 1
		var trimmed: String = _lines[_next].strip_edges()
		_next += 1
		if trimmed.begins_with("["):
			var header: String = trimmed
			var header_comment: String = ""
			var comment_at: int = header.find("#")
			if comment_at >= 0:
				if comment_at + 1 < header.length() and header[comment_at + 1] == "#":
					pass # FrogLord stops looking for a header comment after an escaped '#'.
				else:
					header_comment = header.substr(comment_at + 1).strip_edges(true, false)
					header = header.substr(0, comment_at).strip_edges(false, true)
			if header.is_empty() or not header.ends_with("]"):
				error = "line %d: invalid section header '%s'" % [line_number, header]
				return config
			var left: int = 0
			while left < header.length() and header[left] == "[":
				left += 1
			var right: int = 0
			while right < header.length() and header[header.length() - 1 - right] == "]":
				right += 1
			if left != right:
				error = "line %d: section '%s' has %d '[' but %d ']'" % [line_number, header, left, right]
				return config
			if left > layer + 1:
				error = "line %d: section '%s' is nested too deeply (parent depth %d)" % [line_number, header, layer]
				return config
			var name_length: int = header.length() - left - right
			if name_length <= 0:
				error = "line %d: section has no name" % line_number
				return config
			var child_name: String = unescape_comment(header.substr(left, name_length))
			if left == layer + 1:
				var child: FrogLordConfig = _read_section(left, child_name, header_comment)
				config.add_child(child)
			else:
				_next -= 1 # An ancestor section owns this header.
				return config
			continue
		_read_body_line(config, trimmed, line_number)
	return config


func _read_body_line(config: FrogLordConfig, trimmed: String, line_number: int) -> void:
	var content: String = trimmed
	var i: int = 0
	while i < content.length():
		if content[i] == "#":
			if i + 1 < content.length() and content[i + 1] == "#":
				i += 2
				continue
			content = content.substr(0, i).strip_edges(false, true)
			break
		i += 1
	var split_at: int = -1
	var j: int = 0
	while j < content.length():
		var ch: String = content[j]
		if ch == "\\":
			j += 2
			continue
		if ch == "=":
			split_at = j
			break
		if ch == " ":
			break
		j += 1
	if split_at < 0:
		config.text.append(content)
		return
	var key: String = unescape_key(content.substr(0, split_at))
	if config.has_key(key):
		error = "line %d: the property '%s' was already set in this section" % [line_number, key]
		return
	config.set_value(key, unescape_value(content.substr(split_at + 1)))


## Turns FrogLord's [code]##[/code] escape back into [code]#[/code].
static func unescape_comment(value: String) -> String:
	return value.replace("##", "#")


## Unescapes a value: [code]null[/code] becomes null, [code]"null"[/code] the text "null".
static func unescape_value(value: String) -> Variant:
	if value == "null":
		return null
	if value == "\"null\"":
		return "null"
	return unescape_comment(value)


## Unescapes a key in the same order FrogLord does.
static func unescape_key(key: String) -> String:
	return unescape_comment(key).replace("\\ ", " ").replace("\\=", "=").replace("\\\\", "\\")
