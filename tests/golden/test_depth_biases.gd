extends GutTest
## Independent C ordering-table depth biases applied by terrain, frog and Cave sprite drawing.

const FACTS_PATH: String = "res://tests/golden/synthetic/depth_biases.json"
const PICKUP_TEXTURE: int = 40
const PICKUP_POINTER: int = 0x401000

var _facts: Dictionary = {}

func before_all() -> void:
	_facts = JSON.parse_string(FileAccess.get_file_as_string(FACTS_PATH))

func test_view_biases_match_independent_facts() -> void:
	var terrain: float = _facts.terrain_back
	var frog: float = _facts.frog_forward
	var pickup: float = _facts.pickup_forward
	var firefly: float = _facts.firefly_forward
	assert_eq(MapShaders.TERRAIN_DEPTH_BIAS, terrain, "terrain_back")
	assert_eq(GameplayWorldView.FROG_DEPTH_BIAS, frog, "frog_forward")
	assert_eq(CaveSpriteView.PICKUP_DEPTH_BIAS, pickup, "pickup_forward")
	assert_eq(CaveSpriteView.FIREFLY_DEPTH_BIAS, firefly, "firefly_forward")
	assert_string_contains(MapShaders.terrain_depth_code(), "eye.z - %.1f / 256.0" % terrain)

func test_frog_materials_and_instance_overrides_receive_frog_bias() -> void:
	var frog: float = _facts.frog_forward
	var view := GameplayWorldView.new()
	autofree(view)
	var part: ShaderMaterial = ModelShaders.material(null, ModelShaders.Blend.OPAQUE, false, false)
	var original: ShaderMaterial = ModelShaders.material(null, ModelShaders.Blend.OPAQUE, false, false)
	var frame: ShaderMaterial = ModelShaders.material(null, ModelShaders.Blend.OPAQUE, false, false)
	var override: ShaderMaterial = ModelShaders.material(null, ModelShaders.Blend.OPAQUE, false, false)
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, part)
	var track := ModelMesh.TextureTrack.new()
	track.original = original
	track.frames = [frame]
	view.frog_assets = TerrainFrogAssets.new()
	view.frog_assets.mesh = ModelMesh.new()
	view.frog_assets.mesh.part_meshes = [mesh]
	view.frog_assets.mesh.texture_tracks = [[track]]
	view._frog_model = AnimatedModelInstance.new()
	autofree(view._frog_model)
	var node := MeshInstance3D.new()
	autofree(node)
	node.mesh = mesh
	node.set_surface_override_material(0, override)
	view._frog_model.part_nodes = [node]
	view._apply_frog_depth_bias()
	for material: ShaderMaterial in [part, original, frame, override]:
		var bias: float = material.get_shader_parameter("depth_bias")
		assert_eq(bias, frog)

func test_configured_pickups_and_fireflies_receive_source_biases() -> void:
	var pickup: float = _facts.pickup_forward
	var firefly: float = _facts.firefly_forward
	var view := CaveSpriteView.new()
	add_child_autofree(view)
	var image_names := PackedStringArray()
	image_names.resize(43)
	image_names[41] = "fire_fly"
	image_names[42] = "fire_flya"
	var lists := GameNameLists.new()
	lists.images = NameBank.new()
	lists.images.names = image_names
	var tables := ExeTables.new(null, null, lists)
	var row := PickupData.new()
	row.fly_type = 3
	row.sprite_size = 65536
	row.frame_pointers = PackedInt64Array([PICKUP_POINTER])
	var rows: Array[PickupData] = [row, row, row, row]
	tables._pickups = rows
	tables._pickups_read = true
	tables._bmp_pointers = BmpPointers.new()
	tables._bmp_pointers._id_by_pointer[PICKUP_POINTER] = PICKUP_TEXTURE
	var data := GameData.new()
	data.tables = tables.decoded
	data.names = lists
	var pixels: Array[int] = []
	for _index: int in 10 * 6:
		pixels.append_array([200, 120, 40])
	var specs: Array[SyntheticVlo.Spec] = []
	for identity: int in [PICKUP_TEXTURE, 41, 42, CaveSpriteView.GLOW_TEXTURE_ID]:
		specs.append(SyntheticVlo.spec(8, 4, 2, identity, 0, SyntheticVlo.abgr(pixels)))
	var scene := MapSceneData.new()
	scene.library.add_bank(VloFile.parse(SyntheticVlo.build_vlo(specs)), "CAV_VRAM.VLO")
	var definitions: Array[EntityDefinition] = [_definition(EntityBehavior.Kind.FIREFLY, 0), _definition(EntityBehavior.Kind.PICKUP, 3)]
	var issue: String = view.configure(scene, data, definitions)
	assert_false(issue.contains("fire_fly"), issue)
	assert_false(issue.contains("missing from the supplied banks"), issue)
	assert_eq(view._firefly.size(), 2)
	assert_true(view._pickups.has(3))
	assert_not_null(view._glow)
	for sprite: CaveSpriteView.Sprite in view._firefly:
		var bias: float = sprite.material.get_shader_parameter("depth_bias")
		assert_eq(bias, firefly, "firefly_forward")
	for sprite: CaveSpriteView.Sprite in view._pickups[3].frames + [view._glow]:
		var bias: float = sprite.material.get_shader_parameter("depth_bias")
		assert_eq(bias, pickup, "pickup_forward")

func _definition(kind: EntityBehavior.Kind, pickup_type: int) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.behavior.kind = kind
	definition.pickup_type = pickup_type
	return definition
