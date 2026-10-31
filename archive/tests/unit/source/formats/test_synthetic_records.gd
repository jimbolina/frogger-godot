extends GutTest
## The game suite's synthetic model and texture bank records hold exactly what
## the readers decode from the same specs written as files, apart from values
## that only say where things lie in a file.

## Polygons with environment normals (FrogLord's E3), which have no named constant.
const E3: int = 8
## Values that only say where things lie in a file.
const LAYOUT_FIELDS: Array[String] = ["size", "length", "end_offset", "static_ranges"]


func _differences(expected: Variant, actual: Variant, path: String, found: PackedStringArray) -> void:
	if expected is Resource and actual is Resource:
		var expected_resource: Resource = expected
		var actual_resource: Resource = actual
		for property: Dictionary in expected_resource.get_property_list():
			var usage: int = property["usage"]
			var name: String = property["name"]
			if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or usage & PROPERTY_USAGE_STORAGE == 0 or name in LAYOUT_FIELDS:
				continue
			_differences(expected_resource.get(name), actual_resource.get(name), path + "." + name, found)
		return
	if expected is Array and actual is Array:
		var expected_items: Array = expected
		var actual_items: Array = actual
		if expected_items.size() != actual_items.size():
			found.append("%s: %d items, expected %d" % [path, actual_items.size(), expected_items.size()])
			return
		for i: int in expected_items.size():
			_differences(expected_items[i], actual_items[i], "%s[%d]" % [path, i], found)
		return
	if typeof(expected) != typeof(actual) or expected != actual:
		found.append("%s: %s, expected %s" % [path, str(actual), str(expected)])


func _assert_same(expected: Resource, actual: Resource, label: String) -> void:
	var found := PackedStringArray()
	_differences(expected, actual, label, found)
	assert_eq(found, PackedStringArray(), label)


func _parts() -> Dictionary[String, Array]:
	var full: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.FT4, Color8(10, 20, 30), 7)
	full.poses.append(PackedInt32Array([0, 0, 8, 256, 0, 8, 256, 256, 8, 0, 256, -8]))
	full.flipbook_actions = 1
	full.animated_polygons = PackedInt32Array([0])
	full.animation_images = PackedInt32Array([7, 8, 9])
	full.animation_durations = PackedInt32Array([2, 3])
	full.hilites.append(Vector2i(4, 2))
	full.collprims = 2
	var ranges: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.G4)
	ranges.poses.append(PackedInt32Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]))
	ranges.poses.append(PackedInt32Array([-1, -2, -3, -4, -5, -6, -7, -8, -9, -10, -11, -12]))
	ranges.flipbook_ranges = [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 3)]
	var mixed: SyntheticMof.Part = SyntheticMof.square(MofPolygonType.F4)
	mixed.polygons.append(SyntheticMof.polygon(MofPolygonType.FT3, [0, 1, 2], [0], Color8(1, 2, 3), 11, [0, 0, 255, 0, 255, 255]))
	mixed.polygons.append(SyntheticMof.polygon(MofPolygonType.G3, [0, 1, 2], [0, 0, 0]))
	mixed.polygons.append(SyntheticMof.polygon(MofPolygonType.GT4, [0, 1, 2, 3], [0, 0, 0, 0], Color8(4, 5, 6), 12, [0, 0, 255, 0, 255, 255, 0, 255]))
	mixed.polygons.append(SyntheticMof.polygon(E3, [0, 1, 2], [0, 0, 0, 0]))
	mixed.polygons.append(SyntheticMof.polygon(MofPolygonType.F3, [0, 1, 3], [0]))
	var plain: Array[SyntheticMof.Part] = [SyntheticMof.square(MofPolygonType.F4)]
	var textured: Array[SyntheticMof.Part] = [SyntheticMof.square(MofPolygonType.FT4, Color8(128, 128, 128), 7)]
	var everything: Array[SyntheticMof.Part] = [full, ranges, mixed]
	return {"plain": plain, "textured": textured, "everything": everything}


func test_static_models_match_the_reader() -> void:
	var cases: Dictionary[String, Array] = _parts()
	for label: String in cases:
		var parts: Array[SyntheticMof.Part] = []
		parts.assign(cases[label])
		var decoded: MofFile = MofReader.parse(SyntheticMofBytes.build_static(parts))
		assert_eq(decoded.error, "", label)
		_assert_same(decoded, SyntheticMof.static_file(parts), label)
		_assert_same(decoded.static_models[0], SyntheticMof.static_model(parts), label + " model")


func test_placeholders_match_the_reader() -> void:
	_assert_same(MofReader.parse(SyntheticMofBytes.build_dummy()), SyntheticMof.dummy_file(), "dummy")


func test_animated_models_match_the_reader() -> void:
	var parts: Array[SyntheticMof.Part] = [SyntheticMof.square(MofPolygonType.F4), SyntheticMof.square(MofPolygonType.G4)]
	var bytes: PackedByteArray = SyntheticMofBytes.build_static(parts)
	var model: MofStatic = SyntheticMof.static_model(parts)
	var cases: Array[Dictionary] = [
		{"code": 0, "starts": true, "transforms": [SyntheticMofAnimation.transform(0, [4095, 0, 0, 0, 4095, 0, 0, 0, 4095, 512, -3, 0])],
			"actions": [SyntheticMofAnimation.action(2, 1, [0, 0], [0, 0])]},
		{"code": 2, "starts": false, "transforms": [SyntheticMofAnimation.transform(2, [64, -64, 300, 32, 1, -2, 3])],
			"actions": [SyntheticMofAnimation.action(2, 1, [1], [0, 0]), SyntheticMofAnimation.action(2, 1, [5], [0, 3])]},
		{"code": 5, "starts": true, "transforms": [SyntheticMofAnimation.transform(5, [4096, 0, 0, 0, 0, 0, 0, 32, 32, 32, 1]),
			SyntheticMofAnimation.transform(5, [0, 0, 0, 4096, 100, -101, 0, 64, 16, -32, 3])],
			"actions": [SyntheticMofAnimation.action(2, 2, [0, 1, 0, 0, 1, 2048, 0, 1, 4096], [0, 1, 1, 0], true)]},
		{"code": 1, "starts": true, "transforms": [SyntheticMofAnimation.transform(1, [64, 0, 0, 0, 64, 0, 0, 0, 64, 7, 8, 9])],
			"actions": [SyntheticMofAnimation.action(1, 1, [0, 0, 0], [0], true)]},
	]
	for case: Dictionary in cases:
		var code: int = case["code"]
		var starts: bool = case["starts"]
		var transforms: Array[MofTransform] = []
		var authored_transforms: Array = case["transforms"]
		transforms.assign(authored_transforms)
		var actions: Array[MofAction] = []
		var authored_actions: Array = case["actions"]
		actions.assign(authored_actions)
		var label: String = "code %d" % code
		var decoded: MofFile = MofReader.parse(SyntheticMofAnimationBytes.build([bytes, bytes], code, transforms, actions, starts))
		assert_eq(decoded.error, "", label)
		_assert_same(decoded, SyntheticMofAnimation.animated_file([model, SyntheticMof.static_model(parts)], code, transforms, actions, starts), label)


func test_texture_banks_match_the_reader() -> void:
	var pixels: Array[int] = []
	for i: int in 10 * 6:
		pixels.append_array([i, 0 if i % 3 == 0 else 120, 4])
	var first: SyntheticVlo.Spec = SyntheticVlo.spec(8, 4, 2, 40, VloImage.FLAG_BLACK_IS_TRANSPARENT, SyntheticVlo.abgr(pixels))
	first.vram_x = 300
	first.vram_y = 600
	first.blend_mode = 2
	var second: SyntheticVlo.Spec = SyntheticVlo.spec(1, 1, 0, 41, VloImage.FLAG_TRANSLUCENT, SyntheticVlo.abgr([1, 2, 3]))
	var third: SyntheticVlo.Spec = SyntheticVlo.spec(3, 1, 0, 42, 0, SyntheticVlo.abgr([9, 9, 9, 8, 8, 8, 7, 7, 7]))
	var specs: Array[SyntheticVlo.Spec] = [first, second, third]
	for decode: bool in [true, false]:
		var decoded: VloFile = VloFileReader.parse(SyntheticVloBytes.build_vlo(specs), decode)
		assert_eq(decoded.error, "")
		_assert_same(decoded, SyntheticVlo.bank(specs, decode), "decode %s" % decode)
