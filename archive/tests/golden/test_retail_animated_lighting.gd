extends RetailTest
## Needs the retail files: map light inputs and per-part lit polygon colours of
## posed animated and flipbook models match
## tests/golden/pc-retail-v3.0e/animated_lighting.tsv from
## tools/make_golden_animated_lighting.py, each channel within one step.

const FILE_NAME: String = "animated_lighting.tsv"
const CUSTOM_AMBIENT: int = 1
const SCALED_COLOURS: int = 2
const IDENTITY_ROOT: Array[int] = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]
const QUARTER_TURN_ROOT: Array[int] = [0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 0, 0, 0]

var _data: GameData
var _models: Dictionary[int, MofFile] = {}
var _players: Dictionary[int, ModelAnimationPlayer] = {}
var _lighting: Dictionary[String, MapLighting] = {}


func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))


func after_all() -> void:
	if _data != null:
		_data.close()


func _rows(kind: String) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	for row: PackedStringArray in GoldenFiles.rows(FILE_NAME):
		if row[0] == kind:
			result.append(row)
	return result


func _map_lighting(map_name: String) -> MapLighting:
	if not _lighting.has(map_name):
		var lighting := MapLighting.new()
		var entry: MwiEntry = _data.find_resource(map_name)
		var map: MapFile = _data.read_map(entry.index) if entry != null else null
		if map != null:
			lighting.configure(map.lights)
		_lighting[map_name] = lighting
	return _lighting[map_name]


func _player(resource_id: int) -> ModelAnimationPlayer:
	if not _players.has(resource_id):
		_models[resource_id] = _data.read_model(resource_id)
		_players[resource_id] = ModelAnimationPlayer.new(_models[resource_id])
	return _players[resource_id]


func _variant(lighting: MapLighting, flags: int, scale_bytes: Vector3i, custom: Vector3i) -> MapLighting:
	var multiplier: Vector3 = Vector3(scale_bytes) / 128.0 if (flags & SCALED_COLOURS) != 0 else Vector3.ONE
	var base_ambient: Vector3 = Vector3(custom) if (flags & CUSTOM_AMBIENT) != 0 else lighting.ambient / 16.0
	var variant := MapLighting.new()
	variant.ambient = (base_ambient * multiplier).floor() * 16.0
	variant.directions.assign(lighting.directions)
	for colour: Vector3 in lighting.colours:
		variant.colours.append((colour * multiplier).floor())
	return variant


## The root rotation named by a golden row as a Godot basis (MRRotMatrixY for "y90").
func _root(rotation: String) -> Basis:
	return GameSpace.transform(PackedInt32Array(QUARTER_TURN_ROOT if rotation == "y90" else IDENTITY_ROOT)).basis


func _vector(row: PackedStringArray, at: int) -> Vector3i:
	return Vector3i(row[at].to_int(), row[at + 1].to_int(), row[at + 2].to_int())


func test_map_light_inputs() -> void:
	var rows: Array[PackedStringArray] = _rows("lights")
	assert_eq(rows.size(), 3)
	for row: PackedStringArray in rows:
		var resource_id: int = row[1].to_int()
		var map_name: String = row[2]
		var entry: MwiEntry = _data.find_resource(map_name)
		assert_not_null(entry, map_name)
		if entry == null:
			continue
		assert_eq(entry.index, resource_id, map_name)
		var level: int = FroggerIds.LEVEL_CODES.find(map_name.get_basename())
		assert_eq(_data.map_book_entry(level).map_id(false), resource_id, "%s is the high-poly map" % map_name)
		var lighting: MapLighting = _map_lighting(map_name)
		assert_eq(lighting.ambient, Vector3(_vector(row, 3)) * 16.0, "%s ambient" % map_name)
		var slots: PackedStringArray = row[6].split("/") if row[6] != "-" else PackedStringArray()
		assert_eq(lighting.directions.size(), slots.size(), "%s parallel slots" % map_name)
		assert_eq(lighting.colours.size(), slots.size(), "%s colour slots" % map_name)
		for index: int in mini(slots.size(), lighting.directions.size()):
			var values: PackedStringArray = slots[index].split(":")
			var direction := GameSpace.normal(values[0].to_int(), values[1].to_int(), values[2].to_int())
			var colour := Vector3(values[3].to_int(), values[4].to_int(), values[5].to_int()) * 16.0
			assert_eq(lighting.directions[index], direction, "%s slot %d direction" % [map_name, index])
			assert_eq(lighting.colours[index], colour, "%s slot %d colour" % [map_name, index])


func test_posed_part_lighting() -> void:
	var rows: Array[PackedStringArray] = _rows("sample")
	var compared: int = 0
	var corners: int = 0
	var worst: int = 0
	var failures := PackedStringArray()
	for row: PackedStringArray in rows:
		var resource_id: int = row[1].to_int()
		var player: ModelAnimationPlayer = _player(resource_id)
		var file: MofFile = _models[resource_id]
		if file == null or not player.set_action(row[4].to_int()):
			failures.append("%s: cannot pose action %s" % [row[2], row[4]])
			continue
		player.frame = row[5].to_int()
		var pose: ModelPose = player.sample_pose()
		var part_index: int = row[7].to_int()
		var part: MofPart = file.static_models[player.static_index].parts[part_index]
		var polygon: MofPolygon = part.polygons[row[8].to_int()]
		var normals: PackedInt32Array = part.partcels[pose.partcels[part_index]].normals
		var root: Basis = _root(row[6])
		var world: Basis = root * pose.transforms[part_index].basis
		var lighting: MapLighting = _variant(_map_lighting(row[3]), row[9].to_int(), _vector(row, 10), _vector(row, 13))
		var base_bytes: Vector3i = _vector(row, 16)
		if base_bytes != Vector3i(polygon.red, polygon.green, polygon.blue):
			failures.append("%s: base colour %s" % ["\t".join(row), Vector3i(polygon.red, polygon.green, polygon.blue)])
		var base := Color8(polygon.red, polygon.green, polygon.blue)
		var expected: PackedStringArray = row[19].split("/")
		if expected.size() != polygon.normals.size():
			failures.append("%s: %d corners" % ["\t".join(row), polygon.normals.size()])
			continue
		for corner: int in expected.size():
			var at: int = polygon.normal_of_corner(corner) * 3
			var normal := GameSpace.normal(normals[at], normals[at + 1], normals[at + 2])
			var lit: Color = lighting.shade(base, normal, world)
			var want: PackedStringArray = expected[corner].split(":")
			var got := Vector3i(lit.r8, lit.g8, lit.b8)
			var difference: Vector3i = (got - Vector3i(want[0].to_int(), want[1].to_int(), want[2].to_int())).abs()
			worst = maxi(worst, maxi(difference.x, maxi(difference.y, difference.z)))
			if difference.x > 1 or difference.y > 1 or difference.z > 1:
				failures.append("%s corner %d: got %s" % ["\t".join(row), corner, got])
			corners += 1
		compared += 1
	assert_eq(rows.size(), 1764)
	assert_eq(compared, rows.size(), "every sample row compared")
	assert_eq(corners, 6288)
	assert_lte(worst, 1, "largest channel difference")
	var shown: PackedStringArray = failures.slice(0, 8)
	assert_eq(failures.size(), 0, "%d mismatches\n%s" % [failures.size(), "\n".join(shown)])
