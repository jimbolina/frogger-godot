extends GutTest
## A texture set names the images folder the game draws from and maps
## retail asset paths into it; the retail set maps nothing.


func test_retail_set_leaves_paths_alone() -> void:
	var set: TextureSet = TextureSet.retail()
	assert_eq(set.set_name, TextureSet.RETAIL)
	assert_eq(set.scale, 1)
	assert_true(set.is_retail())
	assert_false(set.linear_filter())
	assert_eq(set.counterpart_path("res://assets/textures/images/t0012.png"), "res://assets/textures/images/t0012.png")


func test_x4_set_maps_images_only() -> void:
	var set: TextureSet = TextureSet.x4()
	assert_eq(set.set_name, TextureSet.X4)
	assert_eq(set.scale, 4)
	assert_false(set.is_retail())
	assert_true(set.linear_filter())
	assert_eq(set.counterpart_path("res://assets/textures/images/t0012.png"), "res://assets/textures/images_x4/t0012.png")
	assert_eq(set.counterpart_path("res://assets/textures/pages/GEN_VRAM+CAV_VRAM/page_03.png"),
		"res://assets/textures/pages/GEN_VRAM+CAV_VRAM/page_03.png", "only the images folder has a counterpart")
	assert_eq(set.counterpart_path("res://assets/textures/banks/CAV_VRAM.tres"), "res://assets/textures/banks/CAV_VRAM.tres")
	assert_eq(set.counterpart_path(""), "")
	assert_eq(set.counterpart_path("user://assets/0123456789abcdef/textures/images/t0012.res"),
		"user://assets/0123456789abcdef/textures/images_x4/t0012.res", "a runtime-imported record keeps its extension")
	assert_eq(TextureSet.retail().counterpart_path("user://assets/0123456789abcdef/textures/images/t0012.res"),
		"user://assets/0123456789abcdef/textures/images/t0012.res")


func test_sets_are_found_by_name() -> void:
	assert_eq(TextureSet.named("").set_name, TextureSet.RETAIL)
	assert_eq(TextureSet.named("retail").set_name, TextureSet.RETAIL)
	assert_eq(TextureSet.named("x4").set_name, TextureSet.X4)
	assert_null(TextureSet.named("x8"))
