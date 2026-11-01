class_name GraphicsSettings
extends Resource
## The player's graphics choices: display, quality, shadows, post-processing, effects and look.
##
## A plain record with its own enums; the presentation layer maps them to
## engine values. The defaults reproduce the accepted modern look, so a
## missing or discarded settings file changes nothing on screen.

## How the game window is shown.
enum WindowMode { WINDOWED, BORDERLESS_FULLSCREEN, EXCLUSIVE_FULLSCREEN }
## Vertical synchronisation.
enum Vsync { DISABLED, ENABLED, ADAPTIVE, MAILBOX }
## How the 3D view is scaled to the window.
enum Scaler { BILINEAR, FSR1, FSR2, METALFX_SPATIAL, METALFX_TEMPORAL }
## Multisample anti-aliasing of the 3D view.
enum Msaa { OFF, X2, X4, X8 }
## Screen-space anti-aliasing.
enum ScreenAa { OFF, FXAA, SMAA }
## Tone mapping curve.
enum Tonemapper { LINEAR, REINHARD, FILMIC, ACES, AGX }
## Soft-shadow filter quality.
enum SoftShadow { HARD, VERY_LOW, LOW, MEDIUM, HIGH, ULTRA }
## How the cave light's range is chosen, in CaveLightShape.Mode order.
enum CaveMode { EXACT_EDGE, FITTED_RANGE }

## Smallest 3D render scale.
const MIN_RENDER_SCALE: float = 0.25
## Largest 3D render scale.
const MAX_RENDER_SCALE: float = 2.0
## Highest frame cap; zero means uncapped.
const MAX_FPS_LIMIT: int = 1000
## Largest FSR sharpness.
const MAX_FSR_SHARPNESS: float = 2.0
## Smallest directional shadow atlas size.
const MIN_SHADOW_ATLAS: int = 512
## Largest directional shadow atlas size.
const MAX_SHADOW_ATLAS: int = 16384

## Window mode.
@export var window_mode: WindowMode = WindowMode.WINDOWED
## Window size in pixels; zero keeps the launch size.
@export var window_size: Vector2i = Vector2i.ZERO
## Vertical synchronisation.
@export var vsync: Vsync = Vsync.ENABLED
## Frame cap; zero means uncapped.
@export var max_fps: int = 0
## 3D render scale relative to the window.
@export var render_scale: float = 1.0
## 3D scaler.
@export var scaler: Scaler = Scaler.BILINEAR
## FSR sharpness; zero is sharpest.
@export var fsr_sharpness: float = 0.2
## Multisample anti-aliasing.
@export var msaa: Msaa = Msaa.OFF
## Screen-space anti-aliasing.
@export var screen_aa: ScreenAa = ScreenAa.OFF
## Temporal anti-aliasing.
@export var taa: bool = false
## Whether real directional shadows are drawn, below the per-launch ceiling.
@export var real_shadows: bool = true
## Directional shadow atlas size in pixels.
@export var shadow_atlas_size: int = 4096
## Soft-shadow filter quality.
@export var soft_shadow_quality: SoftShadow = SoftShadow.LOW
## Directional shadow splits: 1, 2 or 4.
@export var shadow_splits: int = 2
## First split position, as a fraction of the maximum distance.
@export var shadow_split_1: float = 0.25
## Directional shadow maximum distance in grid squares.
@export var shadow_max_distance: float = 32.0
## Shadow depth bias.
@export var shadow_bias: float = 0.05
## Shadow normal bias.
@export var shadow_normal_bias: float = 1.0
## Whether bloom is drawn.
@export var bloom: bool = true
## Bloom intensity.
@export var bloom_intensity: float = 0.8
## Brightness above which colours bloom.
@export var bloom_threshold: float = 1.0
## Tone mapping curve.
@export var tonemapper: Tonemapper = Tonemapper.LINEAR
## Tone mapping exposure.
@export var exposure: float = 1.0
## Screen-space ambient occlusion.
@export var ssao: bool = false
## Brightness of the glow halos around bugs and gold frogs.
@export var glow_halo_strength: float = 2.0
## Whether glowing sprites also light their surroundings.
@export var glow_lights: bool = true
## Whether glow lights are also placed in caves.
@export var glow_lights_in_caves: bool = false
## Energy scale of glow lights.
@export var glow_light_energy: float = 1.0
## Emission scale of lava surfaces.
@export var lava_emission: float = 1.0
## Whether lava surfaces light their surroundings.
@export var lava_lights: bool = true
## Share of an environment-mapped water surface's colour drawn as emission.
@export var water_reflection: float = 0.35
## Specular strength of water surfaces.
@export var water_specular: float = 0.2
## Specular exponent of water surfaces.
@export var water_shininess: float = 512.0
## Strength of the baked vertex colours on terrain.
@export var vertex_tint: float = 1.0
## How the cave light's range is chosen.
@export var cave_light_mode: CaveMode = CaveMode.EXACT_EDGE


## Names of the stored fields, in declaration order.
static func field_names() -> PackedStringArray:
	var names := PackedStringArray()
	for property: Dictionary in GraphicsSettings.new().get_property_list():
		var usage: int = property["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			names.append(str(property["name"]))
	return names


## Why these values are unusable, or "" when they are valid.
func validate() -> String:
	var problems: PackedStringArray = [
		_enum_problem("window_mode", window_mode, WindowMode.size()),
		_window_size_problem(),
		_enum_problem("vsync", vsync, Vsync.size()),
		_int_problem("max_fps", max_fps, 0, MAX_FPS_LIMIT),
		_float_problem("render_scale", render_scale, MIN_RENDER_SCALE, MAX_RENDER_SCALE),
		_enum_problem("scaler", scaler, Scaler.size()),
		_float_problem("fsr_sharpness", fsr_sharpness, 0.0, MAX_FSR_SHARPNESS),
		_enum_problem("msaa", msaa, Msaa.size()),
		_enum_problem("screen_aa", screen_aa, ScreenAa.size()),
		_atlas_problem(),
		_enum_problem("soft_shadow_quality", soft_shadow_quality, SoftShadow.size()),
		"" if shadow_splits in [1, 2, 4] else "shadow_splits %d not 1, 2 or 4" % shadow_splits,
		_float_problem("shadow_split_1", shadow_split_1, 0.0, 1.0),
		_positive_problem("shadow_max_distance", shadow_max_distance),
		_float_problem("shadow_bias", shadow_bias, 0.0, INF),
		_float_problem("shadow_normal_bias", shadow_normal_bias, 0.0, INF),
		_float_problem("bloom_intensity", bloom_intensity, 0.0, INF),
		_float_problem("bloom_threshold", bloom_threshold, 0.0, INF),
		_enum_problem("tonemapper", tonemapper, Tonemapper.size()),
		_positive_problem("exposure", exposure),
		_float_problem("glow_halo_strength", glow_halo_strength, 0.0, INF),
		_float_problem("glow_light_energy", glow_light_energy, 0.0, INF),
		_float_problem("lava_emission", lava_emission, 0.0, INF),
		_float_problem("water_reflection", water_reflection, 0.0, INF),
		_float_problem("water_specular", water_specular, 0.0, INF),
		_float_problem("water_shininess", water_shininess, 0.0, INF),
		_float_problem("vertex_tint", vertex_tint, 0.0, INF),
		_enum_problem("cave_light_mode", cave_light_mode, CaveMode.size()),
	]
	for problem: String in problems:
		if not problem.is_empty():
			return problem
	return ""


## Copies every field of [param other] into this record without emitting [signal Resource.changed].
func assign(other: GraphicsSettings) -> void:
	for field: String in field_names():
		set(field, other.get(field))


## An independent record holding the same values.
func copy() -> GraphicsSettings:
	var result := GraphicsSettings.new()
	result.assign(self)
	return result


func _enum_problem(field: String, value: int, count: int) -> String:
	if value < 0 or value >= count:
		return "%s %d outside 0..%d" % [field, value, count - 1]
	return ""


func _int_problem(field: String, value: int, low: int, high: int) -> String:
	if value < low or value > high:
		return "%s %d outside %d..%d" % [field, value, low, high]
	return ""


func _float_problem(field: String, value: float, low: float, high: float) -> String:
	if not is_finite(value):
		return "%s is not finite" % field
	if value < low or value > high:
		return "%s %s outside %s..%s" % [field, value, low, high]
	return ""


func _positive_problem(field: String, value: float) -> String:
	if not is_finite(value) or value <= 0.0:
		return "%s %s is not a positive number" % [field, value]
	return ""


func _window_size_problem() -> String:
	if window_size == Vector2i.ZERO or (window_size.x > 0 and window_size.y > 0):
		return ""
	return "window_size %s is neither zero nor positive" % window_size


func _atlas_problem() -> String:
	var size: int = shadow_atlas_size
	if size < MIN_SHADOW_ATLAS or size > MAX_SHADOW_ATLAS or (size & (size - 1)) != 0:
		return "shadow_atlas_size %d not a power of two in %d..%d" % [size, MIN_SHADOW_ATLAS, MAX_SHADOW_ATLAS]
	return ""
