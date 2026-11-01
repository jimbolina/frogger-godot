extends GutTest
## GraphicsApplier sets a viewport's quality properties, falls back from MetalFX off the Metal driver and explains interactions.


func _viewport() -> SubViewport:
	var viewport := SubViewport.new()
	add_child_autofree(viewport)
	return viewport


func _sample() -> GraphicsSettings:
	var settings := GraphicsSettings.new()
	settings.msaa = GraphicsSettings.Msaa.X4
	settings.screen_aa = GraphicsSettings.ScreenAa.SMAA
	settings.taa = true
	settings.scaler = GraphicsSettings.Scaler.FSR1
	settings.render_scale = 0.75
	settings.fsr_sharpness = 0.6
	return settings


func test_apply_viewport_sets_every_property() -> void:
	var viewport: SubViewport = _viewport()
	GraphicsApplier.apply_viewport(viewport, _sample())
	assert_eq(viewport.msaa_3d, Viewport.MSAA_4X)
	assert_eq(viewport.screen_space_aa, Viewport.SCREEN_SPACE_AA_SMAA)
	assert_true(viewport.use_taa)
	assert_eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR)
	assert_almost_eq(viewport.scaling_3d_scale, 0.75, 0.0001)
	assert_almost_eq(viewport.fsr_sharpness, 0.6, 0.0001)


func test_defaults_restore_the_plain_viewport() -> void:
	var viewport: SubViewport = _viewport()
	GraphicsApplier.apply_viewport(viewport, _sample())
	GraphicsApplier.apply_viewport(viewport, GraphicsSettings.new())
	assert_eq(viewport.msaa_3d, Viewport.MSAA_DISABLED)
	assert_eq(viewport.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED)
	assert_false(viewport.use_taa)
	assert_eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR)
	assert_almost_eq(viewport.scaling_3d_scale, 1.0, 0.0001)


func test_a_temporal_scaler_turns_taa_off() -> void:
	var viewport: SubViewport = _viewport()
	var settings: GraphicsSettings = _sample()
	settings.scaler = GraphicsSettings.Scaler.FSR2
	GraphicsApplier.apply_viewport(viewport, settings)
	assert_eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR2)
	assert_false(viewport.use_taa)
	assert_true(GraphicsApplier.is_temporal(GraphicsSettings.Scaler.FSR2))
	assert_true(GraphicsApplier.is_temporal(GraphicsSettings.Scaler.METALFX_TEMPORAL))
	assert_false(GraphicsApplier.is_temporal(GraphicsSettings.Scaler.FSR1))


func test_metalfx_falls_back_to_bilinear_off_the_metal_driver() -> void:
	for scaler: GraphicsSettings.Scaler in [
			GraphicsSettings.Scaler.METALFX_SPATIAL, GraphicsSettings.Scaler.METALFX_TEMPORAL]:
		assert_false(GraphicsApplier.scaler_available(scaler, "vulkan"))
		assert_true(GraphicsApplier.scaler_available(scaler, "metal"))
		var viewport: SubViewport = _viewport()
		var settings: GraphicsSettings = _sample()
		settings.scaler = scaler
		GraphicsApplier.apply_viewport(viewport, settings, "vulkan")
		assert_eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR)
		assert_true(viewport.use_taa, "bilinear keeps the chosen TAA")
	assert_true(GraphicsApplier.scaler_available(GraphicsSettings.Scaler.FSR2, "vulkan"))


func test_metalfx_passes_through_on_the_metal_driver() -> void:
	var viewport: SubViewport = _viewport()
	var settings: GraphicsSettings = _sample()
	settings.scaler = GraphicsSettings.Scaler.METALFX_TEMPORAL
	GraphicsApplier.apply_viewport(viewport, settings, "metal")
	assert_eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_METALFX_TEMPORAL)
	assert_false(viewport.use_taa)


func test_notes_explain_the_fallback_and_temporal_scalers() -> void:
	assert_eq(GraphicsApplier.quality_notes(_sample(), "vulkan").size(), 0)
	var metal: GraphicsSettings = _sample()
	metal.scaler = GraphicsSettings.Scaler.METALFX_SPATIAL
	assert_true("Metal driver" in "\n".join(GraphicsApplier.quality_notes(metal, "vulkan")))
	assert_false("Metal driver" in "\n".join(GraphicsApplier.quality_notes(metal, "metal")))
	var temporal: GraphicsSettings = _sample()
	temporal.scaler = GraphicsSettings.Scaler.FSR2
	assert_true("TAA is off" in "\n".join(GraphicsApplier.quality_notes(temporal, "vulkan")))


func test_apply_changed_leaves_the_viewport_alone_for_unrelated_edits() -> void:
	var viewport: SubViewport = _viewport()
	var before := GraphicsSettings.new()
	var after := GraphicsSettings.new()
	after.bloom = false
	after.water_specular = 0.5
	viewport.msaa_3d = Viewport.MSAA_8X
	GraphicsApplier.apply_changed(viewport, before, after)
	assert_eq(viewport.msaa_3d, Viewport.MSAA_8X)
	after.taa = true
	GraphicsApplier.apply_changed(viewport, before, after)
	assert_eq(viewport.msaa_3d, Viewport.MSAA_DISABLED)
	assert_true(viewport.use_taa)
