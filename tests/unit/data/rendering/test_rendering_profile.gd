extends GutTest
## A rendering profile names the renderer it is made for and notes when the
## game runs on another one.


func test_profiles_are_found_by_name() -> void:
	assert_eq(RenderingProfile.named("").profile_name, RenderingProfile.RETAIL)
	assert_eq(RenderingProfile.named("retail").profile_name, RenderingProfile.RETAIL)
	assert_eq(RenderingProfile.named("modern").profile_name, RenderingProfile.MODERN)
	assert_null(RenderingProfile.named("ultra"))


func test_the_retail_profile_runs_on_compatibility() -> void:
	var profile: RenderingProfile = RenderingProfile.retail()
	assert_false(profile.is_modern())
	assert_eq(profile.rendering_method(), RenderingProfile.COMPATIBILITY)
	assert_eq(profile.renderer_note(RenderingProfile.COMPATIBILITY), "")
	var note: String = profile.renderer_note(RenderingProfile.FORWARD_PLUS)
	assert_true(note.contains("retail") and note.contains(RenderingProfile.FORWARD_PLUS), note)


func test_the_modern_profile_runs_on_forward_plus() -> void:
	var profile: RenderingProfile = RenderingProfile.modern()
	assert_true(profile.is_modern())
	assert_eq(profile.rendering_method(), RenderingProfile.FORWARD_PLUS)
	assert_eq(profile.renderer_note(RenderingProfile.FORWARD_PLUS), "")
	assert_eq(profile.renderer_note(RenderingProfile.COMPATIBILITY),
		"rendering profile modern runs on gl_compatibility; shadows and lighting may differ from forward_plus")
