extends RefCounted
## Lexical architecture checks over supplied project sources, without loading them.
##
## This is a conservative dependency scanner, not a GDScript parser or type checker.
## It resolves project class names, literal script loads and extends chains. It
## cannot prove dynamic dispatch, class-name shadowing or dependencies supplied
## from outside this source set; review diagnostics make these gaps explicit.
## Scene lights and environments under res://src/ belong to res://src/presentation/.

const TREE_CALLS: PackedStringArray = [
	"get_tree", "get_node", "get_node_or_null", "has_node", "get_main_loop",
]
const TREE_TYPES: PackedStringArray = ["SceneTree", "NodePath", "PackedScene", "SceneState"]
const GAME_ENVIRONMENT: PackedStringArray = [
	"FileAccess", "DirAccess", "ConfigFile", "ZIPReader", "ZIPPacker",
	"ResourceLoader", "ResourceSaver", "Input", "InputMap", "Time", "OS", "DisplayServer",
]
const DYNAMIC_CALLS: PackedStringArray = [
	"call", "callv", "call_deferred", "call_thread_safe", "call_deferred_thread_group",
	"set_script", "Callable",
]
const DATA_TYPES: PackedStringArray = [
	"Texture2D", "Mesh", "ArrayMesh", "AudioStream", "AudioStreamWAV",
	"Animation", "AnimationLibrary", "PackedScene",
]
const OBJECT_BASES: PackedStringArray = ["RefCounted"]
const DATA_BASES: PackedStringArray = ["RefCounted", "Resource"]
const APPLICATION_IO: PackedStringArray = [
	"res://src/application/loaders/", "res://src/application/storage/",
]
const ARCHIVE: String = "res://archive/"
const SOURCE_ROOTS: PackedStringArray = ["res://src/source/", "res://archive/source/"]
const ARCHIVE_GUARDED: PackedStringArray = [
	"res://src/", "res://scenes/", "res://assets/", "res://tests/", "res://tools/",
]
const RESOURCE_FILES: PackedStringArray = ["tscn", "tres"]
const LIGHTING_TYPES: PackedStringArray = [
	"Light3D", "DirectionalLight3D", "OmniLight3D", "SpotLight3D", "WorldEnvironment", "Environment",
]
const LIGHTING_SCOPE: String = "res://src/"
const LIGHTING_OWNER: String = "res://src/presentation/"
const PROTECTED_LAYERS: PackedStringArray = ["source", "game", "application", "data"]


## A path and line diagnostic, retaining the protected script being checked.
class Violation:
	extends RefCounted
	var path: String
	var line: int
	var rule: String
	var detail: String
	var origin: String

	func _init(source_path: String, source_line: int, rule_name: String,
			message: String, protected_path: String) -> void:
		path = source_path
		line = source_line
		rule = rule_name
		detail = message
		origin = protected_path

	## Formats a diagnostic for command line logs.
	func format() -> String:
		var via: String = "" if path == origin else " (required by %s)" % origin
		return "%s:%d: [%s] %s%s" % [path, line, rule, detail, via]


## A lexical token with source coordinates and literal-string identity.
class Token:
	extends RefCounted
	var value: String
	var line: int
	var column: int
	var is_string: bool

	func _init(text: String, source_line: int, source_column: int,
			string_literal: bool = false) -> void:
		value = text
		line = source_line
		column = source_column
		is_string = string_literal


## A statically discovered dependency and the line that references it.
class Edge:
	extends RefCounted
	var path: String
	var line: int

	func _init(target: String, source_line: int) -> void:
		path = target
		line = source_line


## Indexed declarations, tokens and dependencies for one script.
class Source:
	extends RefCounted
	var tokens: Array[Token] = []
	var edges: Array[Edge] = []
	var base: String = ""
	var base_line: int = 1
	var base_is_path: bool = false
	var name: String = ""


## Checks a synthetic or filesystem-derived map of res:// paths to source text.
## The caller supplies every project script so names and inherited bases resolve;
## scene and resource files in the map are line-scanned for archive references.
func check(sources: Dictionary[String, String]) -> Array[Violation]:
	var records: Dictionary[String, Source] = {}
	var names: Dictionary[String, String] = {}
	var paths: Array[String] = []
	var resources: Array[String] = []
	for path: String in sources:
		if RESOURCE_FILES.has(path.get_extension()):
			resources.append(path)
			continue
		paths.append(path)
		var record := Source.new()
		record.tokens = _tokenize(sources[path])
		_read_declarations(record)
		records[path] = record
		if not record.name.is_empty():
			names[record.name] = path
	paths.sort()
	for path: String in paths:
		_read_edges(path, records[path], names)
	var result: Array[Violation] = []
	for origin: String in paths:
		var layer: String = _protected_layer(origin)
		if layer.is_empty():
			continue
		var root_record: Source = records[origin]
		var allowed: PackedStringArray = _allowed_bases(origin, layer)
		if not _inherits_allowed(origin, allowed, records, names, {}):
			result.append(Violation.new(origin, root_record.base_line, "base",
				"protected script must inherit %s through a resolved base"
					% " or ".join(allowed), origin))
		_visit(origin, origin, layer, records, names, {}, result)
	for path: String in paths:
		_check_lighting(path, records[path], result)
	_check_archive(paths, records, result)
	resources.sort()
	for path: String in resources:
		result.append_array(scan_resource(path, sources[path]))
	return result


## Reports each line of a scene or resource file outside the archive that
## references a path under res://archive/.
static func scan_resource(path: String, text: String) -> Array[Violation]:
	var result: Array[Violation] = []
	if path.begins_with(ARCHIVE):
		return result
	var lines: PackedStringArray = text.split("\n")
	for index: int in range(lines.size()):
		if lines[index].contains(ARCHIVE):
			result.append(Violation.new(path, index + 1, "archive",
				"shipped resource must not reference archived code", path))
	return result


## Whether a res:// path is a protected layer or forbidden to some protected layer.
func classifies(path: String) -> bool:
	if not _protected_layer(path).is_empty():
		return true
	for layer: String in PROTECTED_LAYERS:
		if _forbidden_path(path, layer):
			return true
	return false


func _check_lighting(path: String, record: Source, into: Array[Violation]) -> void:
	if not path.begins_with(LIGHTING_SCOPE) or path.begins_with(LIGHTING_OWNER):
		return
	for index: int in range(record.tokens.size()):
		var token: Token = record.tokens[index]
		if token.is_string or not LIGHTING_TYPES.has(token.value):
			continue
		if index > 0 and record.tokens[index - 1].value == ".":
			continue
		into.append(Violation.new(path, token.line, "lighting-ownership",
			"scene lighting %s belongs under %s" % [token.value, LIGHTING_OWNER], path))


func _check_archive(paths: Array[String], records: Dictionary[String, Source],
		into: Array[Violation]) -> void:
	var tainted: Dictionary[String, bool] = {}
	var changed: bool = true
	while changed:
		changed = false
		for path: String in paths:
			if tainted.has(path) or path.begins_with(ARCHIVE):
				continue
			for edge: Edge in records[path].edges:
				if edge.path.begins_with(ARCHIVE) or tainted.has(edge.path):
					tainted[path] = true
					changed = true
					break
	for origin: String in paths:
		if tainted.has(origin) and _archive_guarded(origin):
			_visit_archive(origin, origin, records, tainted, {}, into)


func _visit_archive(path: String, origin: String, records: Dictionary[String, Source],
		tainted: Dictionary[String, bool], visited: Dictionary[String, bool],
		into: Array[Violation]) -> void:
	if visited.has(path):
		return
	visited[path] = true
	for edge: Edge in records[path].edges:
		if edge.path.begins_with(ARCHIVE):
			into.append(Violation.new(path, edge.line, "archive",
				"shipped code must not depend on archived %s" % edge.path, origin))
		elif tainted.has(edge.path):
			_visit_archive(edge.path, origin, records, tainted, visited, into)


func _archive_guarded(path: String) -> bool:
	for root: String in ARCHIVE_GUARDED:
		if path.begins_with(root):
			return true
	return false


func _read_declarations(record: Source) -> void:
	for index: int in range(record.tokens.size() - 1):
		var token: Token = record.tokens[index]
		var next: Token = record.tokens[index + 1]
		if token.is_string:
			continue
		if token.value == "class_name" and token.column == 1:
			record.name = next.value
		if token.value == "extends" and token.column == 1:
			record.base = next.value
			record.base_line = token.line
			record.base_is_path = next.is_string


func _read_edges(path: String, record: Source, names: Dictionary[String, String]) -> void:
	for index: int in range(record.tokens.size()):
		var token: Token = record.tokens[index]
		if token.is_string:
			if index > 0 and record.tokens[index - 1].value == "extends":
				record.edges.append(Edge.new(_resolve_path(path, token.value), token.line))
			continue
		if names.has(token.value) and token.value != record.name:
			record.edges.append(Edge.new(names[token.value], token.line))
		if _is_loader(record.tokens, index) and _is_literal_load(record.tokens, index):
			record.edges.append(Edge.new(_resolve_path(path, record.tokens[index + 2].value),
				token.line))


func _visit(path: String, origin: String, layer: String,
		records: Dictionary[String, Source], names: Dictionary[String, String],
		visited: Dictionary[String, bool], into: Array[Violation]) -> void:
	if visited.has(path):
		return
	visited[path] = true
	var record: Source = records[path]
	_check_symbols(path, origin, layer, record, records, names, into)
	for edge: Edge in record.edges:
		if edge.path.begins_with(ARCHIVE) and not origin.begins_with(ARCHIVE):
			continue
		if _forbidden_path(edge.path, layer):
			into.append(Violation.new(path, edge.line, "layer",
				"%s must not depend on %s" % [layer, edge.path], origin))
		elif records.has(edge.path):
			_visit(edge.path, origin, layer, records, names, visited, into)
		elif edge.path.get_extension() == "gd":
			into.append(Violation.new(path, edge.line, "review",
				"script dependency is outside the scanned source set: %s" % edge.path, origin))
		elif _is_pure(layer):
			into.append(Violation.new(path, edge.line, "environment",
				"%s cannot load file resources: %s" % [layer, edge.path], origin))


func _check_symbols(path: String, origin: String, layer: String, record: Source,
		records: Dictionary[String, Source], names: Dictionary[String, String],
		into: Array[Violation]) -> void:
	for index: int in range(record.tokens.size()):
		var token: Token = record.tokens[index]
		if token.is_string:
			continue
		var member: bool = index > 0 and record.tokens[index - 1].value == "."
		var invoked: bool = index + 1 < record.tokens.size() \
			and record.tokens[index + 1].value == "(" \
			and not (index > 0 and record.tokens[index - 1].value == "func")
		if not member and _is_tree_type(token.value) \
				and not (path.begins_with("res://src/data/") and DATA_TYPES.has(token.value)):
			into.append(Violation.new(path, token.line, "tree",
				"node/tree dependency %s" % token.value, origin))
		elif token.value == "$" or _is_unique_node_path(record.tokens, index) \
				or (invoked and TREE_CALLS.has(token.value)):
			into.append(Violation.new(path, token.line, "tree",
				"node/tree access %s" % token.value, origin))
		if layer == "game" and token.value == "entity_name" and _entity_name_dispatch(record.tokens, index):
			into.append(Violation.new(path, token.line, "behavior",
				"gameplay must dispatch on resolved behavior kinds, not entity names", origin))
		if not member and GAME_ENVIRONMENT.has(token.value) \
				and _environment_restricted(path, layer):
			into.append(Violation.new(path, token.line, "environment",
				"gameplay must receive external data instead of using %s" % token.value, origin))
		if invoked and (DYNAMIC_CALLS.has(token.value) \
				or token.value == "get_singleton" \
				or (token.value == "instantiate" and index > 1 \
					and record.tokens[index - 2].value == "ClassDB")):
			into.append(Violation.new(path, token.line, "review",
				"dynamic dispatch %s requires explicit architecture review" % token.value, origin))
		if _is_loader(record.tokens, index):
			if not _is_literal_load(record.tokens, index) and not _is_application_io(path):
				into.append(Violation.new(path, token.line, "review",
					"computed resource load requires explicit architecture review", origin))
			if _is_pure(layer) and token.value == "load":
				into.append(Violation.new(path, token.line, "environment",
					"%s cannot perform runtime resource loading" % layer, origin))
		if token.value == "extends" and token.column > 1 \
				and index + 1 < record.tokens.size():
			var base: Token = record.tokens[index + 1]
			var allowed: PackedStringArray = _allowed_bases(path, layer)
			if not _base_is_allowed(path, base.value, base.is_string, allowed, records, names, {}):
				into.append(Violation.new(path, token.line, "base",
					"inner class must inherit %s through a resolved base"
						% " or ".join(allowed), origin))


func _entity_name_dispatch(tokens: Array[Token], index: int) -> bool:
	var line: int = tokens[index].line
	var first: int = index
	while first > 0 and tokens[first - 1].line == line:
		first -= 1
	var cursor: int = first
	while cursor < tokens.size() and tokens[cursor].line == line:
		var token: Token = tokens[cursor]
		if not token.is_string:
			if token.value in ["match", "in", "==", "!="]:
				return true
			if token.value in ["=", "!"] and cursor + 1 < tokens.size() and tokens[cursor + 1].value == "=":
				return true
		cursor += 1
	return false


func _environment_restricted(path: String, layer: String) -> bool:
	if _is_pure(layer):
		return true
	if layer != "application" or not path.begins_with("res://src/application/"):
		return false
	return not _is_application_io(path)


func _is_application_io(path: String) -> bool:
	for exempt: String in APPLICATION_IO:
		if path.begins_with(exempt):
			return true
	return false


func _is_pure(layer: String) -> bool:
	return layer == "game" or layer == "data"


func _allowed_bases(path: String, layer: String) -> PackedStringArray:
	if layer == "data" or path.begins_with("res://src/data/"):
		return DATA_BASES
	return OBJECT_BASES


func _inherits_allowed(path: String, allowed: PackedStringArray,
		records: Dictionary[String, Source], names: Dictionary[String, String],
		seen: Dictionary[String, bool]) -> bool:
	if seen.has(path) or not records.has(path):
		return false
	seen[path] = true
	var record: Source = records[path]
	return _base_is_allowed(path, record.base, record.base_is_path, allowed, records, names, seen)


func _base_is_allowed(path: String, base: String, is_path: bool, allowed: PackedStringArray,
		records: Dictionary[String, Source], names: Dictionary[String, String],
		seen: Dictionary[String, bool]) -> bool:
	if is_path:
		return _inherits_allowed(_resolve_path(path, base), allowed, records, names, seen)
	if names.has(base):
		return _inherits_allowed(names[base], allowed, records, names, seen)
	return allowed.has(base)


func _is_tree_type(value: String) -> bool:
	return TREE_TYPES.has(value) or value == "Node" \
		or (ClassDB.class_exists(value) and ClassDB.is_parent_class(value, "Node"))


func _is_unique_node_path(tokens: Array[Token], index: int) -> bool:
	if tokens[index].value != "%" or index + 1 >= tokens.size():
		return false
	var next: Token = tokens[index + 1]
	if next.is_string or not _is_identifier(next.value.substr(0, 1)):
		return false
	if index == 0 or tokens[index - 1].line < tokens[index].line:
		return true
	return tokens[index - 1].value in ["=", "return", "(", "[", ",", ":"]


func _is_loader(tokens: Array[Token], index: int) -> bool:
	var token: Token = tokens[index]
	if token.is_string or (token.value != "load" and token.value != "preload"):
		return false
	if index + 1 >= tokens.size() or tokens[index + 1].value != "(":
		return false
	if index > 0 and tokens[index - 1].value == "func":
		return false
	if index > 0 and tokens[index - 1].value == ".":
		return index > 1 and tokens[index - 2].value == "ResourceLoader"
	return true


func _is_literal_load(tokens: Array[Token], index: int) -> bool:
	return index + 3 < tokens.size() and tokens[index + 2].is_string \
		and tokens[index + 3].value in [")", ","]


func _protected_layer(path: String) -> String:
	if _is_source(path):
		return "source"
	if path.begins_with("res://src/game/"):
		return "game"
	if path.begins_with("res://src/application/"):
		return "application"
	if path.begins_with("res://src/data/"):
		return "data"
	return ""


func _forbidden_path(path: String, layer: String) -> bool:
	if path.begins_with("res://src/rendering/") \
			or path.begins_with("res://src/presentation/") \
			or path.begins_with("res://src/inspection/") \
			or path.begins_with("res://scenes/") \
			or path.get_extension() in ["tscn", "scn"]:
		return true
	if layer == "application":
		return false
	if path.begins_with("res://src/application/"):
		return true
	if layer == "source" or layer == "data":
		return path.begins_with("res://src/game/")
	return _is_source(path) or path.begins_with("res://src/data/")


func _is_source(path: String) -> bool:
	for root: String in SOURCE_ROOTS:
		if path.begins_with(root):
			return true
	return false


func _resolve_path(source: String, target: String) -> String:
	if target.begins_with("res://") or target.begins_with("user://"):
		return target.simplify_path()
	return source.get_base_dir().path_join(target).simplify_path()


func _is_identifier(character: String) -> bool:
	return character == "_" or character.unicode_at(0) >= 128 \
		or (character >= "a" and character <= "z") \
		or (character >= "A" and character <= "Z") \
		or (character >= "0" and character <= "9")


func _tokenize(source: String) -> Array[Token]:
	var tokens: Array[Token] = []
	var offset: int = 0
	var line: int = 1
	var column: int = 1
	while offset < source.length():
		var character: String = source.substr(offset, 1)
		if character == "\n":
			line += 1
			column = 1
			offset += 1
			continue
		if character in [" ", "\t", "\r"]:
			column += 1
			offset += 1
			continue
		if character == "#":
			while offset < source.length() and source.substr(offset, 1) != "\n":
				offset += 1
				column += 1
			continue
		var start_line: int = line
		var start_column: int = column
		if character in ['"', "'"]:
			var delimiter: String = character
			if source.substr(offset, 3) == character.repeat(3):
				delimiter = character.repeat(3)
			offset += delimiter.length()
			column += delimiter.length()
			var literal: String = ""
			while offset < source.length():
				if source.substr(offset, delimiter.length()) == delimiter:
					offset += delimiter.length()
					column += delimiter.length()
					break
				var piece: String = source.substr(offset, 1)
				if piece == "\\" and offset + 1 < source.length():
					literal += source.substr(offset, 2)
					offset += 2
					column += 2
				else:
					literal += piece
					offset += 1
					if piece == "\n":
						line += 1
						column = 1
					else:
						column += 1
			tokens.append(Token.new(literal.c_unescape(), start_line, start_column, true))
		elif _is_identifier(character):
			var start: int = offset
			while offset < source.length() and _is_identifier(source.substr(offset, 1)):
				offset += 1
				column += 1
			tokens.append(Token.new(source.substr(start, offset - start), start_line, start_column))
		else:
			tokens.append(Token.new(character, line, column))
			offset += 1
			column += 1
	return tokens
