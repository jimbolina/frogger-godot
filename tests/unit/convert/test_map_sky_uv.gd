extends GutTest
## Sky-land uses processed texture-record UV endpoints, including page-edge HIT flags.

func test_sky_texture_span_follows_runtime_hit_flags() -> void:
	var image := VloImage.new()
	image.width = 256
	image.height = 128
	assert_eq(MapMeshBuilder.sky_uv_span(image), Vector2i(256, 128))
	image.flags = VloImage.FLAG_HIT_X
	assert_eq(MapMeshBuilder.sky_uv_span(image), Vector2i(255, 128))
	image.flags = VloImage.FLAG_HIT_X | VloImage.FLAG_HIT_Y
	assert_eq(MapMeshBuilder.sky_uv_span(image), Vector2i(255, 127))

func test_full_page_sky_quad_keeps_distinct_uv_corners() -> void:
	var image := VloImage.new()
	image.texture_id = 7
	image.width = 256
	image.height = 256
	image.padded_width = 256
	image.padded_height = 256
	image.flags = VloImage.FLAG_HIT_X | VloImage.FLAG_HIT_Y
	image.pixels.resize(256 * 256 * 4)
	image.pixels.fill(128)
	var bank := VloFile.new()
	bank.images = [image]
	var scene := MapSceneData.new()
	scene.level = 42
	scene.map = MapFile.new()
	scene.remap = TextureRemap.new()
	scene.sky_land = SkyLandFile.new()
	scene.sky_land.dimensions = Vector2i.ONE
	scene.sky_land.texture_ids = PackedInt32Array([0])
	scene.sky_land.rotations = PackedInt32Array([0])
	scene.sky_remap = TextureRemap.new()
	scene.sky_remap.texture_ids = PackedInt32Array([7])
	scene.library.add_bank(bank)
	scene.preferred = bank
	scene.texture_pages.configure(scene.library)
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	var arrays: Array = built.sky_mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(uvs, PackedVector2Array([Vector2(0, 0), Vector2(255, 0), Vector2(0, 255), Vector2(255, 0), Vector2(255, 255), Vector2(0, 255)]))
	assert_eq((int(uvs[1].x) + image.u) & 255, 255, "right endpoint cannot collapse onto left endpoint after byte wrap")
	scene.sky_land.dimensions = Vector2i(35, 39)
	scene.sky_land.texture_ids.resize(35 * 39)
	scene.sky_land.texture_ids.fill(0)
	scene.sky_land.rotations.resize(35 * 39)
	scene.sky_land.rotations.fill(0)
	built = MapMeshBuilder.new().build(scene)
	assert_eq(built.sky_mesh.get_surface_count(), 1, "source tile chain must fit one draw surface")
	assert_eq(built.sky_atlas.get_height(), 258)
	var material: ShaderMaterial = built.sky_mesh.surface_get_material(0)
	assert_true(material.shader.code.contains("cull_disabled"), "source sky has no NCLIP rejection")
	arrays = built.sky_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(vertices.size(), 35 * 39 * 6)
	var second := VloImage.new()
	second.texture_id = 8
	second.vram_y = 256
	second.width = 256
	second.height = 256
	second.padded_width = 256
	second.padded_height = 256
	second.flags = VloImage.FLAG_HIT_X | VloImage.FLAG_HIT_Y
	second.pixels.resize(256 * 256 * 4)
	second.pixels.fill(240)
	bank.images.append(second)
	scene.library.add_bank(bank)
	scene.sky_remap.texture_ids = PackedInt32Array([7, 8])
	scene.sky_land.texture_ids[1] = 1
	built = MapMeshBuilder.new().build(scene)
	var atlas: Image = built.sky_atlas.get_image()
	assert_eq(atlas.get_height(), 516)
	assert_eq(atlas.get_pixel(20, 0), atlas.get_pixel(20, 1), "top page clamp row")
	assert_eq(atlas.get_pixel(20, 257), atlas.get_pixel(20, 256), "bottom page clamp row")
	assert_eq(atlas.get_pixel(20, 258), atlas.get_pixel(20, 259), "second top clamp row")
	assert_ne(atlas.get_pixel(20, 257), atlas.get_pixel(20, 258), "neighbour pages remain distinct")
