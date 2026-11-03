extends GutTest
## A texture set maps texture ids to a texture pack's files and records each
## accepted image's own scale; the original textures map nothing. Pack images
## are whole multiples from 1 to 16 of the retail padded size, and retail
## image paths name their texture id.


func _pack(name: String) -> TexturePack:
	var pack := TexturePack.new()
	pack.pack_name = name
	pack.folder = "user://texture_packs".path_join(name)
	return pack


func test_the_original_textures_have_no_pack() -> void:
	var set: TextureSet = TextureSet.retail()
	assert_true(set.is_retail())
	assert_eq(set.pack_name(), "")
	assert_eq(set.key(), "")
	assert_false(set.has_source(12))
	assert_eq(set.source_of(12), "")
	assert_eq(set.scale_of(12), 1)


func test_a_pack_maps_only_the_textures_it_supplies_each_at_its_own_scale() -> void:
	var sources: Dictionary[int, String] = {12: "user://texture_packs/crisp/t0012.png", 310: "user://texture_packs/crisp/newfont.png"}
	var set: TextureSet = TextureSet.of_pack(_pack("crisp"), sources)
	assert_false(set.is_retail())
	assert_eq(set.pack_name(), "crisp")
	assert_eq(set.key(), "user://texture_packs/crisp")
	assert_true(set.has_source(12))
	assert_false(set.has_source(13), "a texture the pack omits keeps its retail image")
	assert_eq(set.source_of(310), "user://texture_packs/crisp/newfont.png")
	set.accept(12, 2)
	set.accept(310, 4)
	assert_eq(set.scale_of(12), 2)
	assert_eq(set.scale_of(310), 4, "the scale is per texture")
	assert_eq(set.scale_of(13), 1)
	set.reject(12)
	assert_false(set.has_source(12), "a rejected image falls back to retail")
	assert_eq(set.scale_of(12), 1)
	sources.erase(310)
	assert_true(set.has_source(310), "the set keeps its own copy of the sources")


func test_a_scale_is_a_whole_multiple_from_1_to_16_on_both_axes() -> void:
	assert_eq(TextureSet.scale_for(Vector2i(40, 24), Vector2i(40, 24)), 1)
	assert_eq(TextureSet.scale_for(Vector2i(80, 48), Vector2i(40, 24)), 2)
	assert_eq(TextureSet.scale_for(Vector2i(160, 96), Vector2i(40, 24)), 4)
	assert_eq(TextureSet.scale_for(Vector2i(640, 384), Vector2i(40, 24)), 16)
	assert_eq(TextureSet.scale_for(Vector2i(680, 408), Vector2i(40, 24)), 0, "17 is too large")
	assert_eq(TextureSet.scale_for(Vector2i(100, 60), Vector2i(40, 24)), 0, "2.5 is not whole")
	assert_eq(TextureSet.scale_for(Vector2i(80, 96), Vector2i(40, 24)), 0, "the aspect must match")
	assert_eq(TextureSet.scale_for(Vector2i(20, 12), Vector2i(40, 24)), 0, "smaller than retail")
	assert_eq(TextureSet.scale_for(Vector2i(40, 24), Vector2i.ZERO), 0)


func test_retail_paths_and_file_names_name_their_texture_id() -> void:
	assert_eq(TextureSet.texture_id_of("res://assets/textures/images/t0012.png"), 12)
	assert_eq(TextureSet.texture_id_of("user://assets/0123456789abcdef/textures/images/t1857.res"), 1857)
	assert_eq(TextureSet.texture_id_of("res://assets/textures/lettering/t0012.png"), -1)
	assert_eq(TextureSet.texture_id_of("res://assets/textures/banks/CAV_VRAM.tres"), -1)
	assert_eq(TextureSet.texture_id_of(""), -1)
	assert_eq(TextureSet.texture_id_of_file("T0310.PNG"), 310)
	assert_eq(TextureSet.texture_id_of_file("hi_a.png"), -1)
	assert_eq(TextureSet.texture_id_of_file("t031.png"), -1)
	assert_eq(TextureSet.texture_id_of_file("t03100.png"), -1)
	assert_eq(TextureSet.texture_id_of_file("tabcd.png"), -1)


func test_fonts_are_found_by_name() -> void:
	assert_eq(TextureSet.font_path("newfont"), "fonts/retail/newfont.fnt")
	assert_eq(TextureSet.font_path("angular"), "fonts/angular/frogger_angular.ttf")
