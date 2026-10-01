extends GutTest
## The texture viewer builds its grid from a texture bank without any game files.

const VIEWER_SCENE: String = "res://scenes/tools/texture_viewer.tscn"


func _viewer() -> TextureViewer:
	var scene: PackedScene = load(VIEWER_SCENE)
	var viewer: TextureViewer = scene.instantiate()
	viewer.auto_open = false
	add_child_autofree(viewer)
	return viewer


func test_shows_every_image_of_a_bank() -> void:
	var viewer: TextureViewer = _viewer()
	var bank: PackedByteArray = SyntheticVlo.build_vlo([
		SyntheticVlo.spec(2, 2, 0, 10, 0, SyntheticVlo.abgr([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])),
		SyntheticVlo.spec(1, 1, 2, 11, VloImage.FLAG_BLACK_IS_TRANSPARENT, SyntheticVlo.abgr([0, 0, 0, 0, 0, 0, 0, 0, 0,
			0, 0, 0, 9, 9, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))])
	assert_eq(viewer.load_vlo_bytes("TEST.VLO", bank), 2)
	assert_eq(viewer.cell_count(), 2)
	assert_eq(viewer.current_bank.images[1].texture_id, 11)
	assert_eq(viewer.load_vlo_bytes("BROKEN.VLO", "nope".to_ascii_buffer()), -1)


func test_without_game_data_lists_nothing() -> void:
	var viewer: TextureViewer = _viewer()
	assert_eq(viewer.bank_names().size(), 0)
	assert_eq(viewer.cell_count(), 0)


func test_replacement_with_null_or_invalid_data_clears_the_grid_and_names() -> void:
	var viewer: TextureViewer = _viewer()
	var bank: PackedByteArray = SyntheticVlo.build_vlo([
		SyntheticVlo.spec(1, 1, 0, 10, 0, SyntheticVlo.abgr([1, 2, 3]))])
	for invalid: GameData in [null, GameData.new()]:
		assert_eq(viewer.load_vlo_bytes("TEST.VLO", bank), 1)
		viewer.image_names = NameBank.new()
		if invalid != null:
			invalid.error = "Invalid tables"
		viewer.open_data(invalid)
		assert_null(viewer.current_bank)
		assert_null(viewer.image_names)
		assert_eq(viewer.cell_count(), 0)
		assert_eq(viewer.bank_names().size(), 0)


func test_detached_viewer_releases_display_resources() -> void:
	var viewer: TextureViewer = _viewer()
	var bank: PackedByteArray = SyntheticVlo.build_vlo([
		SyntheticVlo.spec(1, 1, 0, 10, 0, SyntheticVlo.abgr([1, 2, 3]))])
	assert_eq(viewer.load_vlo_bytes("TEST.VLO", bank), 1)
	var old_bank: WeakRef = weakref(viewer.current_bank)
	remove_child(viewer)
	await get_tree().process_frame
	var released_bank: VloFile = old_bank.get_ref()
	assert_null(released_bank)
	assert_null(viewer.current_bank)
	assert_null(viewer.image_names)
	assert_eq(viewer.cell_count(), 0)
