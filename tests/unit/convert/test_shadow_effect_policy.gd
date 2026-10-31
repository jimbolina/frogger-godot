extends GutTest
## The retail profile always draws the blob shadow effects; the modern profile draws them only when the setting keeps the retail effects.


func test_the_retail_profile_draws_the_blob_shadows_under_every_setting() -> void:
	for setting: String in [ShadowEffectPolicy.RETAIL, ShadowEffectPolicy.OFF, "", "unknown"]:
		assert_true(ShadowEffectPolicy.draws_blob_shadows(RenderingProfile.retail(), setting), "retail with '%s'" % setting)
	assert_true(ShadowEffectPolicy.draws_blob_shadows(null, ShadowEffectPolicy.OFF), "no profile draws as retail")


func test_the_modern_profile_hides_them_only_when_off() -> void:
	assert_false(ShadowEffectPolicy.draws_blob_shadows(RenderingProfile.modern(), ShadowEffectPolicy.OFF))
	assert_false(ShadowEffectPolicy.draws_blob_shadows(RenderingProfile.modern(), " Off "))
	assert_true(ShadowEffectPolicy.draws_blob_shadows(RenderingProfile.modern(), ShadowEffectPolicy.RETAIL))
	assert_true(ShadowEffectPolicy.draws_blob_shadows(RenderingProfile.modern(), "unknown"), "only off hides them")


func test_the_default_hides_them_under_the_modern_profile() -> void:
	assert_eq(ShadowEffectPolicy.DEFAULT, ShadowEffectPolicy.OFF)
	assert_false(ShadowEffectPolicy.draws_blob_shadows(RenderingProfile.modern(), ShadowEffectPolicy.DEFAULT))
