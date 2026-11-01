class_name GlowHaloMaterial
extends RefCounted
## Builds the soft glow halo drawn around pickups and gold frogs.
##
## The halo is an additive, unlit quad whose brightness falls from its centre
## as [code]pow(1 - r, falloff)[/code], [code]r[/code] being the distance from
## the centre in half-quad units. The vertex colour carries the glow colour on
## the sprites' scale (128 is neutral, so it is doubled and clamped) and
## [code]halo_strength[/code] lifts the centre above the bloom threshold. The
## vertex stage repeats the unlit sprites' depth bias and projection scale.

## The halo shader.
const SHADER_PATH: String = "res://src/rendering/shaders/glow_halo.gdshader"
## Exponent of the radial falloff.
const DEFAULT_FALLOFF: float = 3.0
## Brightness of the halo's centre relative to its colour.
const DEFAULT_STRENGTH: float = 2.0

static var _shader: Shader = null


## A halo material with [param depth_bias] game units nearer, the shared
## [param projection_scale] and brightness [param halo_strength].
static func create(depth_bias: float, projection_scale: Vector2, halo_strength: float = DEFAULT_STRENGTH) -> ShaderMaterial:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("depth_bias", depth_bias)
	material.set_shader_parameter("projection_scale", projection_scale)
	material.set_shader_parameter("halo_strength", halo_strength)
	material.set_shader_parameter("falloff", DEFAULT_FALLOFF)
	return material
