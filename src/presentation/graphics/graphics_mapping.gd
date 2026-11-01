class_name GraphicsMapping
extends RefCounted
## Maps the [GraphicsSettings] enums to the engine values they choose.


## The [enum DisplayServer.WindowMode] for [param mode]; borderless fullscreen is Godot's plain fullscreen.
static func window_mode(mode: GraphicsSettings.WindowMode) -> DisplayServer.WindowMode:
	match mode:
		GraphicsSettings.WindowMode.BORDERLESS_FULLSCREEN:
			return DisplayServer.WINDOW_MODE_FULLSCREEN
		GraphicsSettings.WindowMode.EXCLUSIVE_FULLSCREEN:
			return DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	return DisplayServer.WINDOW_MODE_WINDOWED


## The [enum DisplayServer.VSyncMode] for [param mode].
static func vsync(mode: GraphicsSettings.Vsync) -> DisplayServer.VSyncMode:
	match mode:
		GraphicsSettings.Vsync.DISABLED:
			return DisplayServer.VSYNC_DISABLED
		GraphicsSettings.Vsync.ADAPTIVE:
			return DisplayServer.VSYNC_ADAPTIVE
		GraphicsSettings.Vsync.MAILBOX:
			return DisplayServer.VSYNC_MAILBOX
	return DisplayServer.VSYNC_ENABLED


## The [enum Viewport.Scaling3DMode] for [param scaler].
static func scaler(scaler_mode: GraphicsSettings.Scaler) -> Viewport.Scaling3DMode:
	match scaler_mode:
		GraphicsSettings.Scaler.FSR1:
			return Viewport.SCALING_3D_MODE_FSR
		GraphicsSettings.Scaler.FSR2:
			return Viewport.SCALING_3D_MODE_FSR2
		GraphicsSettings.Scaler.METALFX_SPATIAL:
			return Viewport.SCALING_3D_MODE_METALFX_SPATIAL
		GraphicsSettings.Scaler.METALFX_TEMPORAL:
			return Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
	return Viewport.SCALING_3D_MODE_BILINEAR


## The [enum Viewport.MSAA] for [param samples].
static func msaa(samples: GraphicsSettings.Msaa) -> Viewport.MSAA:
	match samples:
		GraphicsSettings.Msaa.X2:
			return Viewport.MSAA_2X
		GraphicsSettings.Msaa.X4:
			return Viewport.MSAA_4X
		GraphicsSettings.Msaa.X8:
			return Viewport.MSAA_8X
	return Viewport.MSAA_DISABLED


## The [enum Viewport.ScreenSpaceAA] for [param filter].
static func screen_aa(filter: GraphicsSettings.ScreenAa) -> Viewport.ScreenSpaceAA:
	match filter:
		GraphicsSettings.ScreenAa.FXAA:
			return Viewport.SCREEN_SPACE_AA_FXAA
		GraphicsSettings.ScreenAa.SMAA:
			return Viewport.SCREEN_SPACE_AA_SMAA
	return Viewport.SCREEN_SPACE_AA_DISABLED


## The [enum Environment.ToneMapper] for [param curve].
static func tonemapper(curve: GraphicsSettings.Tonemapper) -> Environment.ToneMapper:
	match curve:
		GraphicsSettings.Tonemapper.REINHARD:
			return Environment.TONE_MAPPER_REINHARDT
		GraphicsSettings.Tonemapper.FILMIC:
			return Environment.TONE_MAPPER_FILMIC
		GraphicsSettings.Tonemapper.ACES:
			return Environment.TONE_MAPPER_ACES
		GraphicsSettings.Tonemapper.AGX:
			return Environment.TONE_MAPPER_AGX
	return Environment.TONE_MAPPER_LINEAR


## The [enum RenderingServer.ShadowQuality] for [param quality].
static func soft_shadow(quality: GraphicsSettings.SoftShadow) -> RenderingServer.ShadowQuality:
	match quality:
		GraphicsSettings.SoftShadow.VERY_LOW:
			return RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW
		GraphicsSettings.SoftShadow.LOW:
			return RenderingServer.SHADOW_QUALITY_SOFT_LOW
		GraphicsSettings.SoftShadow.MEDIUM:
			return RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
		GraphicsSettings.SoftShadow.HIGH:
			return RenderingServer.SHADOW_QUALITY_SOFT_HIGH
		GraphicsSettings.SoftShadow.ULTRA:
			return RenderingServer.SHADOW_QUALITY_SOFT_ULTRA
	return RenderingServer.SHADOW_QUALITY_HARD


## The [enum DirectionalLight3D.ShadowMode] for [param splits] of 1, 2 or 4; anything else is two splits.
static func shadow_mode(splits: int) -> DirectionalLight3D.ShadowMode:
	match splits:
		1:
			return DirectionalLight3D.SHADOW_ORTHOGONAL
		4:
			return DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	return DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS


## The [enum CaveLightShape.Mode] for [param mode].
static func cave_mode(mode: GraphicsSettings.CaveMode) -> CaveLightShape.Mode:
	if mode == GraphicsSettings.CaveMode.FITTED_RANGE:
		return CaveLightShape.Mode.FITTED_RANGE
	return CaveLightShape.Mode.EXACT_EDGE
