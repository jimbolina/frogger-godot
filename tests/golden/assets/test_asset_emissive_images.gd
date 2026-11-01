extends AssetTest
## The hand-authored glowing-image table under assets/rendering/ loads, is
## well formed and names only images the committed name list knows. It is an
## asset consistency check, not a retail-fact golden.


func test_the_table_loads_and_validates() -> void:
	var table: EmissiveImageTable = catalog().emissive_images()
	assert_not_null(table)
	assert_eq(catalog().problems.size(), 0, "\n".join(catalog().problems))
	assert_gt(table.entries.size(), 0)
	assert_eq(table.validate(), PackedStringArray())


func test_every_name_resolves_to_a_texture() -> void:
	var table: EmissiveImageTable = catalog().emissive_images()
	var images: NameBank = catalog().names.images
	for entry: EmissiveImage in table.entries:
		assert_gte(images.index_of(entry.image_name), 0, entry.image_name)
	var diagnostics := PackedStringArray()
	assert_eq(EmissiveSurfaces.resolve(table, images, diagnostics).size(), table.entries.size())
	assert_eq(diagnostics, PackedStringArray())


func test_the_volcano_levels_have_glowing_surfaces() -> void:
	for code: String in ["VOL1", "VOL2", "VOL3"]:
		var scene: MapSceneData = MapSceneData.load_level(catalog(), FroggerIds.level_from_code(code))
		assert_eq(scene.error, "", code)
		var drawn: int = 0
		for polygon: MapPolygon in scene.map.polygons:
			if polygon.texture_id >= 0 and scene.emissive.has(scene.remap.global_id(polygon.texture_id)):
				drawn += 1
		assert_gt(drawn, 0, "%s draws an emissive image" % code)
