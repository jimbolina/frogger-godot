extends RetailTest
## Every available map detail resolves its rendering dependencies through the EXE.


func test_every_map_detail_resolves_textures_and_lighting_data() -> void:
	var data: GameData = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))
	assert_eq(data.error, "")
	var count: int = 0
	for row: MapBookEntry in data.tables.map_book().entries:
		if row.is_dummy() or row.high_map_id <= 0:
			continue
		for low_poly: bool in [false, true]:
			var scene: MapSceneData = MapSceneData.load_level(data, row.level, low_poly)
			assert_eq(scene.error, "", "%s low=%s" % [row.code(), low_poly])
			if not scene.error.is_empty():
				continue
			var missing: Dictionary[int, bool] = {}
			for polygon: MapPolygon in scene.map.polygons:
				if polygon.texture_id >= 0 and scene.image_for_local(polygon.texture_id) == null:
					missing[polygon.texture_id] = true
			for animation: MapAnimation in scene.map.animations:
				for local_id: int in animation.texture_ids:
					if scene.image_for_local(local_id) == null:
						missing[local_id] = true
			assert_eq(missing.size(), 0, "%s missing texture IDs %s" % [row.code(), missing.keys()])
			if row.use_cave_lights:
				assert_true(scene.cave_enabled, "%s named cave light found" % row.code())
				assert_gt(scene.cave_max_r2, scene.cave_min_r2)
			if scene.sky_land != null:
				for local_id: int in scene.sky_land.texture_ids:
					assert_not_null(scene.library.image_for_local(scene.sky_remap, local_id, scene.preferred))
			count += 1
	assert_eq(count, 78)
	assert_eq(data.map_entries().size(), 78)
	data.close()
