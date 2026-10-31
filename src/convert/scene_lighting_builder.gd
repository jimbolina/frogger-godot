class_name SceneLightingBuilder
extends RefCounted
## Maps the C model-lighting recipe of a [MapLighting] onto linear scene light.
##
## Stored values become fractions [code]a = A / 4096[/code] and
## [code]p = P / 4096[/code]. The ambient is [code]gamma(a)[/code] and each
## parallel slot adds what it brightens a fully facing surface by:
## [code]max(gamma(a + p) - gamma(a), 0)[/code], per channel. A slot's energy is
## its largest channel times [constant LAMBERT_SCALE]; its colour is the slot
## divided by that channel, in sRGB. With shadows on, the slot of largest
## luminance casts them.

## Energy multiplier that corrects the renderer's diffuse normalisation.
const LAMBERT_SCALE: float = 1.0
## Exponent turning stored fractions into linear light.
const GAMMA: float = 2.2
## Stored value of full light.
const STORED_ONE: float = 4096.0
## Rec. 709 luminance weights of linear channels.
const LUMINANCE: Vector3 = Vector3(0.2126, 0.7152, 0.0722)
## Largest vertical component that keeps [constant Vector3.UP] as the up vector.
const VERTICAL_LIMIT: float = 0.999


## The modern lighting of [param lighting]; [param shadows] lets its brightest slot cast shadows.
## A slot with a zero direction lights nothing, as in C, and is kept black.
static func from_lighting(lighting: MapLighting, shadows: bool = true) -> SceneLightingSpec:
	var spec := SceneLightingSpec.new()
	spec.shadows = shadows
	var stored_ambient: Vector3 = lighting.ambient / STORED_ONE
	spec.ambient = gamma_of(stored_ambient)
	var caster: int = -1
	var brightest: float = -1.0
	for index: int in lighting.directions.size():
		var direction: Vector3 = lighting.directions[index]
		var parallel: Vector3 = Vector3.ZERO
		if not direction.is_zero_approx():
			parallel = (gamma_of(stored_ambient + lighting.colours[index] / STORED_ONE) - spec.ambient).max(Vector3.ZERO)
		var light := SceneLightingSpec.Light.new()
		light.basis = forward_basis(direction)
		light.colour = light_colour(parallel)
		light.energy = light_energy(parallel)
		spec.lights.append(light)
		var luminance: float = parallel.dot(LUMINANCE)
		if shadows and luminance > brightest:
			brightest = luminance
			caster = index
	if caster >= 0:
		spec.lights[caster].casts_shadow = true
	return spec


## Linear light of stored fraction [param x]: [code]clamp(x, 0, 1) ^ 2.2[/code].
static func gamma(x: float) -> float:
	return pow(clampf(x, 0.0, 1.0), GAMMA)


## [method gamma] of each channel of [param stored].
static func gamma_of(stored: Vector3) -> Vector3:
	return Vector3(gamma(stored.x), gamma(stored.y), gamma(stored.z))


## A light basis whose minus Z axis is [param direction]; [constant Basis.IDENTITY] for a zero direction.
## Near-vertical directions take [constant Vector3.FORWARD] as the up vector.
static func forward_basis(direction: Vector3) -> Basis:
	if direction.is_zero_approx():
		return Basis.IDENTITY
	var forward: Vector3 = direction.normalized()
	var up: Vector3 = Vector3.FORWARD if absf(forward.y) > VERTICAL_LIMIT else Vector3.UP
	return Basis.looking_at(forward, up)


## Energy of linear slot [param parallel]: its largest channel times [constant LAMBERT_SCALE].
static func light_energy(parallel: Vector3) -> float:
	return maxf(parallel.x, maxf(parallel.y, parallel.z)) * LAMBERT_SCALE


## sRGB colour of linear slot [param parallel] scaled to a largest channel of one; white when black.
static func light_colour(parallel: Vector3) -> Color:
	var peak: float = maxf(parallel.x, maxf(parallel.y, parallel.z))
	if peak <= 0.0:
		return Color.WHITE
	return Color(parallel.x / peak, parallel.y / peak, parallel.z / peak).linear_to_srgb()
