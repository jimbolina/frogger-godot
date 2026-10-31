class_name SceneTint
extends RefCounted
## Linear form of a committed colour scale and custom ambient for modern lighting.
##
## The scale multiplies a model's lit colour; the ambient, when its alpha is
## one, replaces the scene ambient for that model. Committed modulations:
## [br]- Frog edge fade: scaled grey [code](g, g, g)[/code], g from 128 down to 0
## outside the fade rectangle ([method FrogTint.edge_fade]).
## [br]- Frog drowning: custom ambient (32, 64, 64) with the sinking scale of
## [method FrogTint.drowning_scale].
## [br]- Volcano char: scale and ambient both (24, 0, 0) ([method FrogTint.set_scale_colours]).
## [br]- Frog reset: a nonzero map header colour as custom ambient, unscaled ([method FrogTint.reset]).
## [br]- Cave fade: scaled grey by distance from the frog's light ([EntityScaleColours]).
## [br]- Turtle dive and Jungle hippo: the dive colour scale with custom ambient (64, 64, 192).
## [br]- Beaver dive: the height colour scale with custom ambient (64, 64, 192).
## [br]- Swamp rat: custom ambient (255, 255, 255), or (255, 0, 255) while splashing.
## [br]- Checkpoint: custom ambient (160, 160, 160).
## [br]- Desert crack: scaled grey from 128 upward as it drops, so above one.

## Colour-scale byte that leaves a colour unchanged.
const NEUTRAL_SCALE: float = 128.0
## Custom ambient byte of full light: the byte times 16, over 4096.
const AMBIENT_ONE: float = 256.0

## Linear per-channel multiplier; one when unscaled, above one for bytes above 128.
var scale: Vector3 = Vector3.ONE
## Linear custom ambient with alpha one, or transparent black when there is none.
var ambient: Color = Color(0.0, 0.0, 0.0, 0.0)


## The tint of [param colour_scale] bytes when [param scaled] and [param custom_ambient] bytes when [param custom].
static func of(colour_scale: Vector3i, custom_ambient: Vector3i, scaled: bool, custom: bool) -> SceneTint:
	var tint := SceneTint.new()
	if scaled:
		tint.scale = Vector3(_scale_gamma(colour_scale.x), _scale_gamma(colour_scale.y), _scale_gamma(colour_scale.z))
	if custom:
		tint.ambient = Color(SceneLightingBuilder.gamma(custom_ambient.x / AMBIENT_ONE),
			SceneLightingBuilder.gamma(custom_ambient.y / AMBIENT_ONE),
			SceneLightingBuilder.gamma(custom_ambient.z / AMBIENT_ONE), 1.0)
	return tint


static func _scale_gamma(byte: int) -> float:
	return pow(maxf(byte / NEUTRAL_SCALE, 0.0), SceneLightingBuilder.GAMMA)
