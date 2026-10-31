extends GutTest
## Tracked synthetic catalogs exercise every viewer's borrowed/owned lifetime contract.

const SCENES: PackedStringArray = ["res://scenes/tools/model_viewer.tscn", "res://scenes/tools/map_viewer.tscn", "res://scenes/tools/terrain_viewer.tscn"]


## An empty catalog that records whether it was closed.
class TrackedCatalog:
	extends AssetCatalog
	var closed: bool = false

	func _init() -> void:
		version_name = "synthetic"
		mwi = MwiIndex.new()
		names = GameNameLists.new()
		tables = GameTables.new()
		tables.map_book_table = MapBook.new()
		tables.theme_book_table = ThemeBook.new()

	## Marks the catalog closed.
	func close() -> void:
		closed = true


func _data() -> TrackedCatalog:
	return TrackedCatalog.new()


func _viewer(path: String) -> Node:
	var scene: PackedScene = load(path)
	var viewer: Node = scene.instantiate()
	viewer.set("auto_open", false)
	add_child(viewer)
	return viewer


func test_freeing_borrowed_viewers_keeps_shared_catalog_open() -> void:
	for path: String in SCENES:
		var data: TrackedCatalog = _data()
		var first: Node = _viewer(path)
		var second: Node = _viewer("res://scenes/tools/model_viewer.tscn")
		first.call("open_data", data)
		first.call("open_data", data)
		second.call("open_data", data)
		first.free()
		assert_false(data.closed, path + " borrowed catalog remains usable by another viewer")
		var second_data: AssetCatalog = second.get("data")
		assert_same(second_data, data)
		second.free()
		assert_false(data.closed, path + " caller still owns the catalog")


func test_independent_owned_viewers_close_only_their_own_catalog() -> void:
	for path: String in SCENES:
		var first_data: TrackedCatalog = _data()
		var second_data: TrackedCatalog = _data()
		var first: Node = _viewer(path)
		var second: Node = _viewer(path)
		first.call("open_data", first_data, true)
		second.call("open_data", second_data, true)
		first.free()
		assert_true(first_data.closed, path + " owned catalog closes on exit")
		assert_false(second_data.closed, path + " independent catalog remains open")
		second.free()
		assert_true(second_data.closed)


func test_replacement_closes_owned_data_and_preserves_borrowed_data() -> void:
	for path: String in SCENES:
		var owned: TrackedCatalog = _data()
		var borrowed: TrackedCatalog = _data()
		var replacement: TrackedCatalog = _data()
		var viewer: Node = _viewer(path)
		viewer.call("open_data", owned, true)
		viewer.call("open_data", borrowed)
		assert_true(owned.closed, path + " replacement closes owned catalog")
		viewer.call("open_data", replacement, true)
		assert_false(borrowed.closed, path + " replacement preserves borrowed catalog")
		viewer.call("open_data", null)
		assert_true(replacement.closed, path + " null replacement closes owned catalog")
		viewer.free()


func test_same_object_retains_ownership_and_can_be_explicitly_adopted() -> void:
	for path: String in SCENES:
		var owned: TrackedCatalog = _data()
		var viewer: Node = _viewer(path)
		viewer.call("open_data", owned, true)
		viewer.call("open_data", owned)
		assert_false(owned.closed, path + " same object was not closed")
		viewer.free()
		assert_true(owned.closed, path + " same object retains ownership")
		var adopted: TrackedCatalog = _data()
		viewer = _viewer(path)
		viewer.call("open_data", adopted)
		viewer.call("open_data", adopted, true)
		assert_false(adopted.closed, path + " explicit adoption does not close data")
		viewer.free()
		assert_true(adopted.closed)


func test_invalid_replacement_preserves_borrowed_catalog_and_closes_owned_catalog() -> void:
	for path: String in SCENES:
		var borrowed: TrackedCatalog = _data()
		var invalid: TrackedCatalog = _data()
		invalid.error = "Invalid synthetic catalog"
		var viewer: Node = _viewer(path)
		viewer.call("open_data", borrowed)
		viewer.call("open_data", invalid, true)
		assert_false(borrowed.closed, path)
		viewer.free()
		assert_true(invalid.closed, path + " invalid owned catalog closes")


func test_detaching_live_viewers_releases_owned_data_but_preserves_borrowed_catalog() -> void:
	for path: String in SCENES:
		var borrowed: TrackedCatalog = _data()
		var owned: TrackedCatalog = _data()
		var first: Node = _viewer(path)
		var second: Node = _viewer(path)
		first.call("open_data", borrowed)
		second.call("open_data", owned, true)
		remove_child(first)
		remove_child(second)
		await get_tree().process_frame
		var first_data: AssetCatalog = first.get("data")
		var second_data: AssetCatalog = second.get("data")
		assert_null(first_data)
		assert_null(second_data)
		assert_false(borrowed.closed, path + " detached viewer released borrowed reference")
		assert_true(owned.closed, path + " detached owned viewer closes catalog")
		first.free()
		second.free()
