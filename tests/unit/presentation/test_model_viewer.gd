extends GutTest
## The model viewer, driven with made-up models. Needs no game files.

const VIEWER_SCENE: String = "res://scenes/tools/model_viewer.tscn"

var _viewer: ModelViewer


func before_each() -> void:
	var scene: PackedScene = load(VIEWER_SCENE)
	_viewer = scene.instantiate() as ModelViewer
	_viewer.auto_open = false
	add_child_autofree(_viewer)


func test_shows_a_model_from_bytes() -> void:
	var parts: Array[SyntheticMof.Part] = [SyntheticMof.square(MofPolygonType.F4), SyntheticMof.square(MofPolygonType.G4)]
	assert_eq(_viewer.load_model_bytes("TEST.XMR", SyntheticMof.build_static(parts)), 4)
	assert_eq(_viewer.part_node_count(), 2)
	assert_eq(_viewer.visible_part_count(), 2)
	assert_string_contains(_viewer.facts_text(), "2 parts")
	assert_string_contains(_viewer.facts_text(), "F4 1, G4 1")


func test_a_placeholder_shows_nothing() -> void:
	assert_eq(_viewer.load_model_bytes("NULL", SyntheticMof.build_dummy()), 0)
	assert_eq(_viewer.part_node_count(), 0)


func test_bad_bytes_are_refused() -> void:
	assert_eq(_viewer.load_model_bytes("BAD.XMR", "not a model at all".to_ascii_buffer()), -1)
	assert_eq(_viewer.part_node_count(), 0)


func test_an_animated_file_shows_its_first_model() -> void:
	var inside: PackedByteArray = SyntheticMof.build_static([SyntheticMof.square(MofPolygonType.F4)])
	assert_eq(_viewer.load_model_bytes("TEST.XAR", SyntheticMof.build_animated([inside, inside])), 2)
	assert_eq(_viewer.current_model.static_models.size(), 2)


func test_without_game_data_nothing_is_listed() -> void:
	assert_eq(_viewer.wad_names().size(), 0)
	assert_eq(_viewer.load_wad_model("THEME_GEN_HI.WAD", 0), -1)
	assert_eq(_viewer.load_model_by_name("GEN_FROG.XAR"), -1)
