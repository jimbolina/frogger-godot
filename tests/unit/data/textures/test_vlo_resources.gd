extends GutTest
## VloFile survives a resource save and load with pixels, textures and its texture-id lookup.

const PATH: String = "user://test_vlo_resources.tres"


func after_all() -> void:
	DirAccess.remove_absolute(PATH)


func test_bank_round_trip_rebuilds_texture_lookup() -> void:
	var spec: SyntheticVlo.Spec = SyntheticVlo.spec(2, 1, 0, 77, VloImage.FLAG_2D_SPRITE, SyntheticVlo.abgr([1, 2, 3, 4, 5, 6]))
	var bank: VloFile = SyntheticVlo.bank([spec])
	assert_eq(bank.error, "")
	assert_eq(ResourceSaver.save(bank, PATH), OK)
	var loaded := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as VloFile
	assert_not_null(loaded)
	assert_eq(loaded.size(), 1)
	assert_eq(loaded.find_texture(77), loaded.images[0])
	assert_null(loaded.find_texture(78))
	assert_eq(loaded.images[0].pixels, bank.images[0].pixels)
	assert_eq(loaded.images[0].unpadded_pixels(), bank.images[0].unpadded_pixels())
	assert_eq(loaded.images[0].texture.get_image().get_data(), bank.images[0].texture.get_image().get_data())
