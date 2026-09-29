class_name LegacyConfigParser
extends RefCounted
## Reads FrogLord's older configuration dialect: game version files and name lists.
##
## This mirrors the rules of FrogLord's [code]file/config/Config.java[/code]
## exactly, so every shipped [code].cfg[/code] means the same thing here as in
## FrogLord:
## [br]- Everything from the first [code]#[/code] on a line is a comment; there
##   is no escape for it. Trailing whitespace is removed, leading whitespace is kept.
## [br]- Blank lines are skipped. A line of just [code]``[/code] stands for an
##   intentionally empty text line.
## [br]- [code][Name][/code] opens a child one level deeper than the current
##   section; [code][[Name]][/code] a grandchild, and so on. Each nested section
##   must be exactly one level deeper than its parent, and bracket counts must balance.
## [br]- A line is a [code]key=value[/code] pair when it contains [code]=[/code]
##   and the part before the first [code]=[/code] has no space. Any other line is
##   text, and from the first text line on, every later line of that section is
##   text too, even if it looks like a pair.
## [br]- A repeated key overwrites the earlier value.

## Why the last parse failed, or an empty string after a successful parse.
var error: String = ""


## Parses [param source] into a tree rooted at a section named
## [param root_name]. Returns null and sets [member error] on a syntax error.
func parse(source: String, root_name: String = "") -> FrogLordConfig:
	error = ""
	var lines: PackedStringArray = source.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var root := FrogLordConfig.new(root_name, 0)
	_load(root, lines)
	return null if not error.is_empty() else root


func _load(config: FrogLordConfig, lines: PackedStringArray) -> void:
	var reading_text: bool = false
	var i: int = 0
	while i < lines.size():
		var line: String = strip_line(lines[i])
		if line.is_empty():
			i += 1
			continue
		if line == "``":
			line = ""
		if line.begins_with("[") and line.ends_with("]"):
			var new_layer: int = _section_layer(line)
			if new_layer < 0:
				return
			var expected_layer: int = config.layer + 1
			if new_layer != expected_layer:
				error = "'%s' is not the right layer (found %d, expected %d)" % [line, new_layer, expected_layer]
				return
			var child_name: String = line.substr(new_layer, line.length() - 2 * new_layer)
			var child_lines := PackedStringArray()
			i += 1
			while i < lines.size():
				var child_line: String = strip_line(lines[i])
				if child_line.begins_with("[") and child_line.ends_with("]"):
					var child_layer: int = _section_layer(child_line)
					if child_layer < 0:
						return
					if child_layer <= expected_layer:
						break
				child_lines.append(child_line)
				i += 1
			var child := FrogLordConfig.new(child_name, new_layer)
			_load(child, child_lines)
			if not error.is_empty():
				return
			config.add_child(child)
			continue
		var equals_at: int = line.find("=")
		var key: String = line if equals_at < 0 else line.substr(0, equals_at)
		if reading_text or equals_at < 0 or key.contains(" "):
			reading_text = true
			config.text.append(line)
		else:
			config.set_value(key, line.substr(equals_at + 1))
		i += 1


## Removes a line's comment and trailing whitespace the way FrogLord does
## (everything from the first [code]#[/code]; leading whitespace is kept).
static func strip_line(line: String) -> String:
	var hash_at: int = line.find("#")
	var kept: String = line if hash_at < 0 else line.substr(0, hash_at)
	return kept.rstrip(" \t\n\r\f\v")


func _section_layer(line: String) -> int:
	var open_count: int = 0
	while open_count < line.length() and line[open_count] == "[":
		open_count += 1
	var close_count: int = 0
	while close_count < line.length() and line[line.length() - 1 - close_count] == "]":
		close_count += 1
	if open_count != close_count:
		error = "section header '%s' has unbalanced brackets (%d open, %d close)" % [line, open_count, close_count]
		return -1
	return open_count
