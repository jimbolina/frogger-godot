extends GutTest
## Effect image resolution order, the frozen C fallback and bank lookups without player files.

func _names(pairs: String) -> NameBank:
	return NameBank.from_indexed_config(FrogLordConfig.parse_legacy(pairs), "Image")

func _image(id: int) -> VloImage:
	var image := VloImage.new()
	image.texture_id = id
	return image

func test_without_executable_data_the_c_generators_and_names_apply() -> void:
	var fallback: EffectResources = EffectResources.resolve(null, null, null, null, null)
	assert_false(fallback.generators.from_executable)
	assert_eq(fallback.generators.records.size(), 13)
	assert_eq(fallback.generators.pop_colours, ExeParticleGenerators.C_POP_COLOURS)
	assert_eq(fallback.texture_ids, {"glow_1727": 1727} as Dictionary[String, int])
	assert_eq(fallback.resolutions["glow_1727"], "fixed")
	assert_eq(fallback.missing.size(), EffectResources.SYMBOLS.size() - 1)
	assert_true(fallback.diagnostics.has("Effects use the frozen C particle generators"))
	assert_eq(fallback.generator_texture_ids("PGIN_hilite_exhaust"), PackedInt32Array([-1]))
	var named: EffectResources = EffectResources.resolve(null, null, null, null, _names("38=tongue_tip\n1163=frog_smoke1\n1060=bison6\n"))
	assert_eq([named.texture_id("im_tongue_tip"), named.resolutions["im_tongue_tip"]], [38, "name"])
	assert_eq(named.generator_texture_ids("PGIN_hilite_exhaust"), PackedInt32Array([38]), "The C exhaust draws the tongue tip")
	assert_eq(named.generator_texture_ids("PGIN_hilite_dust"), PackedInt32Array([-1, -1, -1, -1, -1, 1060]))
	assert_eq(named.texture_id("im_ripple_tim1"), -1, "Ripples have no FrogLord name")
	assert_true(named.missing.has("im_ripple_tim1"))
	assert_false(named.missing.has("im_frog_smoke1"))

func test_executable_records_precede_names_and_disagreements_are_reported() -> void:
	var generators := ExeParticleGenerators.new()
	generators.from_executable = true
	for row: Array in [["PGIN_hilite_fire", 1163], ["PGIN_frog_slip_effect", 1163], ["PGIN_frog_water_bubble", 102]]:
		var record := ParticleGeneratorRecord.new()
		var id: int = row[1]
		record.name = row[0]
		record.texture_kind = ParticleGeneratorRecord.TextureKind.TEXTURE
		record.texture_ids.append(id)
		generators.records.append(record)
	var dust := ParticleGeneratorRecord.new()
	dust.name = "PGIN_hilite_dust"
	dust.texture_kind = ParticleGeneratorRecord.TextureKind.TEXTURE_LIST
	dust.texture_ids = PackedInt32Array([1065, 1061, 1062, 1063, 1064, 1060])
	generators.records.append(dust)
	var resources: EffectResources = EffectResources.resolve(generators, null, null, null, _names("1163=frog_smoke1\n101=wake2\n63=gen_shadow\n"))
	assert_eq([resources.texture_id("im_frog_smoke1"), resources.resolutions["im_frog_smoke1"]], [1163, "exe"])
	assert_eq([resources.texture_id("im_wake2"), resources.resolutions["im_wake2"]], [102, "exe"])
	assert_eq([resources.texture_id("im_bison1"), resources.texture_id("im_bison6")], [1065, 1060])
	assert_eq([resources.texture_id("im_gen_shadow"), resources.resolutions["im_gen_shadow"]], [63, "name"])
	assert_true(resources.diagnostics.has("Effect image im_wake2 is texture 102 in the executable but FrogLord names texture 101"))
	assert_eq(resources.generator_texture_ids("PGIN_hilite_dust"), dust.texture_ids)
	generators.records[1].texture_ids[0] = 1164
	var split: EffectResources = EffectResources.resolve(generators, null, null, null, null)
	assert_eq(split.texture_id("im_frog_smoke1"), 1163)
	assert_true(split.diagnostics.has("Effect image im_frog_smoke1 has executable sources that disagree (1163 and 1164); using 1163"))

func test_images_come_from_the_first_library_holding_them() -> void:
	var resources: EffectResources = EffectResources.resolve(null, null, null, null, _names("38=tongue_tip\n63=gen_shadow\n"))
	var scene_bank := VloFile.new()
	scene_bank.images.append(_image(38))
	var resident_bank := VloFile.new()
	resident_bank.images.append(_image(38))
	resident_bank.images.append(_image(1727))
	var scene := TextureLibrary.new()
	scene.add_bank(scene_bank)
	var resident := TextureLibrary.new()
	resident.add_bank(resident_bank)
	var libraries: Array[TextureLibrary] = [scene, null, resident]
	resources.attach_images(libraries)
	assert_eq(resources.images.keys(), ["im_tongue_tip", "glow_1727"])
	assert_eq(resources.images["im_tongue_tip"], scene_bank.images[0])
	assert_eq(resources.images["glow_1727"], resident_bank.images[1])
	assert_true(resources.missing.has("im_gen_shadow"), "A resolved image outside the banks is missing")
	assert_eq(resources.missing.size(), EffectResources.SYMBOLS.size() - 2)
