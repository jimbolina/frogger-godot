extends GutTest
## Discovers value-copy contracts and checks every script field and nested container.

const OWNERS: Dictionary[String, String] = {
	"EntityRun": "test_entity_run.gd",
	"PathRunner": "test_path_runner.gd",
	"GameplayCamera": "test_gameplay_camera.gd",
	"FrogAnimationController": "test_frog_animation.gd",
	"FrogAnimationContext": "test_frog_animation.gd",
}

var _scripts: Dictionary[String, Script] = {}

func test_value_copies_include_every_field_and_detach_nested_values() -> void:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var path: String = entry.path
		var name: String = entry.class
		if path.begins_with("res://src/game/"):
			_scripts[name] = load(path)
	var checked: int = 0
	for name: String in _scripts:
		var script: Script = _scripts[name]
		if not script.source_code.contains("\nfunc copy(") or OWNERS.has(name):
			continue
		var original: Object = (script as GDScript).new()
		_fill(original, 17)
		var duplicate: Object = original.call("copy")
		var expected: Variant = _facts(original)
		var complete: bool = _facts(duplicate) == expected
		assert_true(complete, name + " copies every field")
		_fill(original, 103)
		var source_isolated: bool = _facts(duplicate) == expected
		assert_true(source_isolated, name + " isolates source mutation")
		var changed: Variant = _facts(original)
		_fill(duplicate, 211)
		var copy_isolated: bool = _facts(original) == changed
		assert_true(copy_isolated, name + " isolates copy mutation")
		checked += 1
	assert_gt(checked, 25, "Value-copy discovery must cover the domain")

func _fields(value: Object) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for field: Dictionary in value.get_property_list():
		var usage: int = field.usage
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			result.append(field)
	return result

func _fill(value: Object, seed: int) -> void:
	var index: int = 0
	for field: Dictionary in _fields(value):
		index += 1
		var name: StringName = field.name
		var kind: int = field.type
		var hint: String = field.class_name if kind == TYPE_OBJECT else field.hint_string
		var previous: Variant = value.get(name)
		if kind == TYPE_OBJECT and hint == "RefCounted" and previous == null:
			if value is FrogCollisionPose and name == &"probes":
				previous = FrogCollisionQuery.Sample.new()
			else:
				fail_test("Unresolved object field: " + String(name))
		value.set(name, _sample(kind, previous, hint, seed + index))

func _sample(kind: int, previous: Variant, hint: String, seed: int) -> Variant:
	match kind:
		TYPE_BOOL:
			var boolean: bool = previous
			return not boolean
		TYPE_INT:
			return seed
		TYPE_FLOAT:
			return float(seed) + 0.25
		TYPE_STRING:
			return "sample-%d" % seed
		TYPE_STRING_NAME:
			return StringName("sample-%d" % seed)
		TYPE_VECTOR2I:
			return Vector2i(seed, seed + 1)
		TYPE_VECTOR3I:
			return Vector3i(seed, seed + 1, seed + 2)
		TYPE_VECTOR2:
			return Vector2(seed, seed + 1)
		TYPE_VECTOR3:
			return Vector3(seed, seed + 1, seed + 2)
		TYPE_RECT2I:
			return Rect2i(seed, seed + 1, seed + 2, seed + 3)
		TYPE_PACKED_INT32_ARRAY:
			return PackedInt32Array([seed, seed + 1, seed + 2])
		TYPE_PACKED_INT64_ARRAY:
			return PackedInt64Array([seed, seed + 1])
		TYPE_PACKED_BYTE_ARRAY:
			return PackedByteArray([seed % 256, (seed + 1) % 256])
		TYPE_PACKED_STRING_ARRAY:
			return PackedStringArray(["sample-%d" % seed])
		TYPE_OBJECT:
			var nested: Object = previous
			if nested == null:
				if not _scripts.has(hint):
					fail_test("Unhandled object type: " + hint)
					return null
				nested = (_scripts[hint] as GDScript).new()
			_fill(nested, seed)
			return nested
		TYPE_ARRAY:
			var items: Array = previous
			if items.is_empty():
				var script: Script = items.get_typed_script()
				if script != null:
					items.append((script as GDScript).new())
				else:
					items.append(_sample(items.get_typed_builtin(), null, "", seed))
			for index: int in items.size():
				items[index] = _sample(typeof(items[index]), items[index], "", seed + index)
			return items
		TYPE_DICTIONARY:
			var items: Dictionary = previous
			if items.is_empty():
				var key: Variant = _sample(items.get_typed_key_builtin(), null, "", seed)
				var script: Script = items.get_typed_value_script()
				items[key] = (script as GDScript).new() if script != null else _sample(items.get_typed_value_builtin(), null, "", seed)
			for key: Variant in items:
				items[key] = _sample(typeof(items[key]), items[key], "", seed)
			return items
	fail_test("Unhandled copy field type %s (%s)" % [type_string(kind), hint])
	return previous

func _facts(value: Variant) -> Variant:
	if value is Object:
		var object: Object = value
		var result: Dictionary = {}
		for field: Dictionary in _fields(object):
			var name: StringName = field.name
			result[name] = _facts(object.get(name))
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_facts(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = _facts(value[key])
		return result
	return value
