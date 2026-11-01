class_name SceneLightingSpec
extends RefCounted
## Node-free description of a map's modern lighting: the linear ambient, up to
## three directional lights and the shadow settings a presentation node applies.

## Render layer of the meshes that cast real shadows.
const SHADOW_CASTER_LAYER: int = 1 << 19


## One directional light taken from a C parallel-light slot.
class Light extends RefCounted:
	## Light node basis; its minus Z axis is the direction the C light travels.
	var basis: Basis = Basis.IDENTITY
	## sRGB [member DirectionalLight3D.light_color], largest channel one.
	var colour: Color = Color.WHITE
	## [member DirectionalLight3D.light_energy].
	var energy: float = 0.0
	## Whether this light casts the scene's shadows.
	var casts_shadow: bool = false


## Linear ambient for the environment ambient colour and the frogger_model_ambient shader global.
var ambient: Vector3 = Vector3.ZERO
## Directional lights in C slot order.
var lights: Array[SceneLightingSpec.Light] = []
## Whether real shadows are enabled.
var shadows: bool = false
## Directional shadow splits.
var shadow_splits: int = 2
## First split position, as a fraction of the maximum distance.
var split_1: float = 0.25
## Directional shadow maximum distance in grid squares.
var max_distance: float = 32.0
## Fraction of the maximum distance where shadows start to fade.
var fade_start: float = 0.8
## Shadow depth bias.
var bias: float = 0.05
## Shadow normal bias.
var normal_bias: float = 1.0
## Shadow blur.
var blur: float = 1.0
