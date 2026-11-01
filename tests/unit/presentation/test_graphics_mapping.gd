extends GutTest
## Every graphics settings enum value maps to its engine value.


func test_window_modes() -> void:
	assert_eq(GraphicsMapping.window_mode(GraphicsSettings.WindowMode.WINDOWED), DisplayServer.WINDOW_MODE_WINDOWED)
	assert_eq(GraphicsMapping.window_mode(GraphicsSettings.WindowMode.BORDERLESS_FULLSCREEN), DisplayServer.WINDOW_MODE_FULLSCREEN)
	assert_eq(GraphicsMapping.window_mode(GraphicsSettings.WindowMode.EXCLUSIVE_FULLSCREEN), DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func test_vsync_modes() -> void:
	assert_eq(GraphicsMapping.vsync(GraphicsSettings.Vsync.DISABLED), DisplayServer.VSYNC_DISABLED)
	assert_eq(GraphicsMapping.vsync(GraphicsSettings.Vsync.ENABLED), DisplayServer.VSYNC_ENABLED)
	assert_eq(GraphicsMapping.vsync(GraphicsSettings.Vsync.ADAPTIVE), DisplayServer.VSYNC_ADAPTIVE)
	assert_eq(GraphicsMapping.vsync(GraphicsSettings.Vsync.MAILBOX), DisplayServer.VSYNC_MAILBOX)


func test_scalers() -> void:
	assert_eq(GraphicsMapping.scaler(GraphicsSettings.Scaler.BILINEAR), Viewport.SCALING_3D_MODE_BILINEAR)
	assert_eq(GraphicsMapping.scaler(GraphicsSettings.Scaler.FSR1), Viewport.SCALING_3D_MODE_FSR)
	assert_eq(GraphicsMapping.scaler(GraphicsSettings.Scaler.FSR2), Viewport.SCALING_3D_MODE_FSR2)
	assert_eq(GraphicsMapping.scaler(GraphicsSettings.Scaler.METALFX_SPATIAL), Viewport.SCALING_3D_MODE_METALFX_SPATIAL)
	assert_eq(GraphicsMapping.scaler(GraphicsSettings.Scaler.METALFX_TEMPORAL), Viewport.SCALING_3D_MODE_METALFX_TEMPORAL)


func test_msaa_sample_counts() -> void:
	assert_eq(GraphicsMapping.msaa(GraphicsSettings.Msaa.OFF), Viewport.MSAA_DISABLED)
	assert_eq(GraphicsMapping.msaa(GraphicsSettings.Msaa.X2), Viewport.MSAA_2X)
	assert_eq(GraphicsMapping.msaa(GraphicsSettings.Msaa.X4), Viewport.MSAA_4X)
	assert_eq(GraphicsMapping.msaa(GraphicsSettings.Msaa.X8), Viewport.MSAA_8X)


func test_screen_space_filters() -> void:
	assert_eq(GraphicsMapping.screen_aa(GraphicsSettings.ScreenAa.OFF), Viewport.SCREEN_SPACE_AA_DISABLED)
	assert_eq(GraphicsMapping.screen_aa(GraphicsSettings.ScreenAa.FXAA), Viewport.SCREEN_SPACE_AA_FXAA)
	assert_eq(GraphicsMapping.screen_aa(GraphicsSettings.ScreenAa.SMAA), Viewport.SCREEN_SPACE_AA_SMAA)


func test_tone_mappers() -> void:
	assert_eq(GraphicsMapping.tonemapper(GraphicsSettings.Tonemapper.LINEAR), Environment.TONE_MAPPER_LINEAR)
	assert_eq(GraphicsMapping.tonemapper(GraphicsSettings.Tonemapper.REINHARD), Environment.TONE_MAPPER_REINHARDT)
	assert_eq(GraphicsMapping.tonemapper(GraphicsSettings.Tonemapper.FILMIC), Environment.TONE_MAPPER_FILMIC)
	assert_eq(GraphicsMapping.tonemapper(GraphicsSettings.Tonemapper.ACES), Environment.TONE_MAPPER_ACES)
	assert_eq(GraphicsMapping.tonemapper(GraphicsSettings.Tonemapper.AGX), Environment.TONE_MAPPER_AGX)


func test_soft_shadow_qualities() -> void:
	assert_eq(GraphicsMapping.soft_shadow(GraphicsSettings.SoftShadow.HARD), RenderingServer.SHADOW_QUALITY_HARD)
	assert_eq(GraphicsMapping.soft_shadow(GraphicsSettings.SoftShadow.VERY_LOW), RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
	assert_eq(GraphicsMapping.soft_shadow(GraphicsSettings.SoftShadow.LOW), RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	assert_eq(GraphicsMapping.soft_shadow(GraphicsSettings.SoftShadow.MEDIUM), RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	assert_eq(GraphicsMapping.soft_shadow(GraphicsSettings.SoftShadow.HIGH), RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	assert_eq(GraphicsMapping.soft_shadow(GraphicsSettings.SoftShadow.ULTRA), RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)


func test_shadow_splits() -> void:
	assert_eq(GraphicsMapping.shadow_mode(1), DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert_eq(GraphicsMapping.shadow_mode(2), DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	assert_eq(GraphicsMapping.shadow_mode(4), DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_eq(GraphicsMapping.shadow_mode(3), DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "an unknown count is two splits")


func test_cave_modes() -> void:
	assert_eq(GraphicsMapping.cave_mode(GraphicsSettings.CaveMode.EXACT_EDGE), CaveLightShape.Mode.EXACT_EDGE)
	assert_eq(GraphicsMapping.cave_mode(GraphicsSettings.CaveMode.FITTED_RANGE), CaveLightShape.Mode.FITTED_RANGE)


func test_every_enum_value_is_covered() -> void:
	assert_eq(GraphicsSettings.WindowMode.size(), 3)
	assert_eq(GraphicsSettings.Vsync.size(), 4)
	assert_eq(GraphicsSettings.Scaler.size(), 5)
	assert_eq(GraphicsSettings.Msaa.size(), 4)
	assert_eq(GraphicsSettings.ScreenAa.size(), 3)
	assert_eq(GraphicsSettings.Tonemapper.size(), 5)
	assert_eq(GraphicsSettings.SoftShadow.size(), 6)
	assert_eq(GraphicsSettings.CaveMode.size(), 2)
