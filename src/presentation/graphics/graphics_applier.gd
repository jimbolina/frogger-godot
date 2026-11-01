class_name GraphicsApplier
extends RefCounted
## Applies the engine-wide [GraphicsSettings]: the window, a viewport's 3D quality and the global shadow filters.
##
## Scene lighting, bloom and the map look follow the live profile in their own
## views; this class covers only what lives on the display server, the engine,
## a viewport or the rendering server. A temporal scaler does its own
## anti-aliasing, so TAA is switched off under it, and a scaler the driver
## cannot run falls back to bilinear.

const _WINDOW_FIELDS: PackedStringArray = ["window_mode", "window_size", "vsync", "max_fps"]
const _VIEWPORT_FIELDS: PackedStringArray = [
	"render_scale", "scaler", "fsr_sharpness", "msaa", "screen_aa", "taa",
]
const _SHADOW_FIELDS: PackedStringArray = ["shadow_atlas_size", "soft_shadow_quality"]


## Applies the window, [param viewport] and global shadow settings of [param settings].
static func apply_all(viewport: Viewport, settings: GraphicsSettings) -> void:
	apply_window(settings)
	apply_viewport(viewport, settings)
	apply_shadows_global(settings)


## Applies only the groups whose fields differ between [param previous] and [param settings],
## so an unrelated edit never moves or resizes the window.
static func apply_changed(viewport: Viewport, previous: GraphicsSettings, settings: GraphicsSettings) -> void:
	if _differs(previous, settings, _WINDOW_FIELDS):
		apply_window(settings)
	if _differs(previous, settings, _VIEWPORT_FIELDS):
		apply_viewport(viewport, settings)
	if _differs(previous, settings, _SHADOW_FIELDS):
		apply_shadows_global(settings)


## Sets the window mode, the windowed size (centred on its screen, only when nonzero), vsync and the frame cap.
static func apply_window(settings: GraphicsSettings) -> void:
	var mode: DisplayServer.WindowMode = GraphicsMapping.window_mode(settings.window_mode)
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	var size: Vector2i = settings.window_size
	if mode == DisplayServer.WINDOW_MODE_WINDOWED and size != Vector2i.ZERO \
			and DisplayServer.window_get_size() != size:
		DisplayServer.window_set_size(size)
		var area: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		var corner: Vector2i = area.position + (area.size - size) / 2
		DisplayServer.window_set_position(corner.max(area.position))
	DisplayServer.window_set_vsync_mode(GraphicsMapping.vsync(settings.vsync))
	Engine.max_fps = settings.max_fps


## Sets [param viewport]'s anti-aliasing and 3D scaling from [param settings] for the rendering
## [param driver], the current one when empty.
static func apply_viewport(viewport: Viewport, settings: GraphicsSettings, driver: String = "") -> void:
	var scaler: GraphicsSettings.Scaler = effective_scaler(settings.scaler, driver)
	viewport.msaa_3d = GraphicsMapping.msaa(settings.msaa)
	viewport.screen_space_aa = GraphicsMapping.screen_aa(settings.screen_aa)
	viewport.use_taa = settings.taa and not is_temporal(scaler)
	viewport.scaling_3d_mode = GraphicsMapping.scaler(scaler)
	viewport.scaling_3d_scale = settings.render_scale
	viewport.fsr_sharpness = settings.fsr_sharpness


## Sets the directional shadow atlas size and the directional and positional soft-shadow filters.
static func apply_shadows_global(settings: GraphicsSettings) -> void:
	var quality: RenderingServer.ShadowQuality = GraphicsMapping.soft_shadow(settings.soft_shadow_quality)
	RenderingServer.directional_shadow_atlas_set_size(settings.shadow_atlas_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(quality)
	RenderingServer.positional_soft_shadow_filter_set_quality(quality)


## Whether the rendering [param driver], the current one when empty, can run [param scaler];
## MetalFX needs the Metal driver.
static func scaler_available(scaler: GraphicsSettings.Scaler, driver: String = "") -> bool:
	if scaler == GraphicsSettings.Scaler.METALFX_SPATIAL or scaler == GraphicsSettings.Scaler.METALFX_TEMPORAL:
		var name: String = driver if not driver.is_empty() else RenderingServer.get_current_rendering_driver_name()
		return name == "metal"
	return true


## [param scaler] when the rendering [param driver] can run it, else bilinear.
static func effective_scaler(scaler: GraphicsSettings.Scaler, driver: String = "") -> GraphicsSettings.Scaler:
	return scaler if scaler_available(scaler, driver) else GraphicsSettings.Scaler.BILINEAR


## Whether [param scaler] is a temporal upscaler, which brings its own anti-aliasing.
static func is_temporal(scaler: GraphicsSettings.Scaler) -> bool:
	return scaler == GraphicsSettings.Scaler.FSR2 or scaler == GraphicsSettings.Scaler.METALFX_TEMPORAL


## Plain notes on how the quality choices in [param settings] interact on the rendering
## [param driver], the current one when empty, for the panel to show.
static func quality_notes(settings: GraphicsSettings, driver: String = "") -> PackedStringArray:
	var notes := PackedStringArray()
	var scaler: GraphicsSettings.Scaler = effective_scaler(settings.scaler, driver)
	if scaler != settings.scaler:
		notes.append("MetalFX needs the Metal driver; bilinear is used.")
	if is_temporal(scaler):
		notes.append("The temporal scaler does its own anti-aliasing; TAA is off.")
		if settings.msaa != GraphicsSettings.Msaa.OFF:
			notes.append("MSAA adds little under a temporal scaler.")
	if scaler == GraphicsSettings.Scaler.BILINEAR and settings.render_scale < 1.0:
		notes.append("Bilinear upscaling blurs; FSR keeps edges sharper.")
	if scaler != GraphicsSettings.Scaler.FSR1 and scaler != GraphicsSettings.Scaler.FSR2:
		notes.append("FSR sharpness applies only to FSR scalers.")
	return notes


static func _differs(first: GraphicsSettings, second: GraphicsSettings, fields: PackedStringArray) -> bool:
	for field: String in fields:
		if first.get(field) != second.get(field):
			return true
	return false
