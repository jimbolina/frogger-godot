extends GutTest
## The blob shadow effects draw unless the setting is off.


func test_off_hides_them() -> void:
	assert_false(ShadowEffectPolicy.draws_blob_shadows(ShadowEffectPolicy.OFF))
	assert_false(ShadowEffectPolicy.draws_blob_shadows(" Off "))


func test_any_other_setting_draws_them() -> void:
	for setting: String in [ShadowEffectPolicy.RETAIL, "", "unknown"]:
		assert_true(ShadowEffectPolicy.draws_blob_shadows(setting), "setting '%s'" % setting)


func test_the_default_hides_them() -> void:
	assert_eq(ShadowEffectPolicy.DEFAULT, ShadowEffectPolicy.OFF)
	assert_false(ShadowEffectPolicy.draws_blob_shadows(ShadowEffectPolicy.DEFAULT))
