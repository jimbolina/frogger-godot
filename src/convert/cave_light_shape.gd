class_name CaveLightShape
extends RefCounted
## Shape of the modern profile's cave omni light, matched to the retail cave grey ramp.
##
## Retail cave terrain multiplies its texel by [method ramp], a grey that
## falls linearly in squared distance from the frog between the minimum and
## maximum squared radii ([method MapLighting.cave_intensity]). A Godot
## [OmniLight3D] with attenuation exponent zero instead weights its light by
## [method window] inside its range. [constant Mode.EXACT_EDGE] ends the light
## where the ramp ends; [constant Mode.FITTED_RANGE] also fits the range,
## which matches the inside better but leaks light past the ramp's edge. Both
## take the energy from [method fit_energy]. Radii are squared game units;
## ranges and distances are Godot units (game units over 256).

## How the light's range is chosen.
enum Mode { EXACT_EDGE, FITTED_RANGE }

## The mode the game applies.
const DEFAULT_MODE: Mode = Mode.EXACT_EDGE
## Lift of the light above the frog in Godot units, so the frog is not inside its own light.
const HEIGHT: float = 0.5
## Environment ambient energy while the cave light is on.
const CAVE_AMBIENT: float = 0.02
## Game units per Godot unit.
const UNITS_PER_SQUARE: float = 256.0
## C distance between the maximum and minimum squared radii (ent_cav.c).
const BAND: int = 0x100000
## Rings sampled by [method fit_energy].
const FIT_RINGS: int = 512
## The fit spans squared distances up to this multiple of the maximum squared radius.
const FIT_REACH: int = 4
## Smallest range scale [constant Mode.FITTED_RANGE] considers.
const SCALE_LOW: float = 1.0
## Largest range scale [constant Mode.FITTED_RANGE] considers; [constant FIT_REACH] covers it.
const SCALE_HIGH: float = 2.0
## Golden-section steps of the range-scale search.
const SCALE_STEPS: int = 32
const UNSIGNED32: int = 0xffffffff


## The light's range for maximum squared radius [param max_r2]: the ramp's
## edge [code]sqrt(max_r2) / 256[/code] under [constant Mode.EXACT_EDGE], or
## that edge times [method fitted_scale] under [constant Mode.FITTED_RANGE];
## zero without a positive radius.
static func range_of(max_r2: int, mode: Mode) -> float:
	if max_r2 <= 0:
		return 0.0
	if mode == Mode.EXACT_EDGE:
		return edge_of(max_r2)
	return edge_of(max_r2) * fitted_scale(max_r2)


## Where the ramp starts to fall, [code]sqrt(min_r2) / 256[/code].
static func inner_of(min_r2: int) -> float:
	return sqrt(maxf(float(min_r2), 0.0)) / UNITS_PER_SQUARE


## The ramp's edge, [code]sqrt(max_r2) / 256[/code].
static func edge_of(max_r2: int) -> float:
	return sqrt(maxf(float(max_r2), 0.0)) / UNITS_PER_SQUARE


## The light energy for the radii under [param mode]: [method fit_energy] at [method range_of].
static func energy_of(min_r2: int, max_r2: int, mode: Mode) -> float:
	if max_r2 <= 0:
		return 0.0
	return fit_energy(min_r2, max_r2, range_of(max_r2, mode))


## Godot's omni attenuation at exponent zero: [code](1 - (d / R)^4)^2[/code]
## inside [param reach], zero at and beyond it.
static func window(distance: float, reach: float) -> float:
	if reach <= 0.0 or distance >= reach:
		return 0.0
	var ratio: float = distance / reach
	var quartic: float = ratio * ratio
	quartic = quartic * quartic
	return (1.0 - quartic) * (1.0 - quartic)


## The factor retail cave terrain multiplies its texel by at squared distance
## [param distance_r2]: the grey of [method MapLighting.cave_intensity] over
## 255, doubled as the terrain doubles vertex colours, clamped at one.
static func ramp(distance_r2: int, min_r2: int, max_r2: int) -> float:
	return minf(2.0 * MapLighting.cave_intensity(distance_r2, min_r2, max_r2) / 255.0, 1.0)


## The least-squares energy that makes [code]energy * window[/code] at
## [param reach] follow [method ramp], weighted by area.
##
## Samples [constant FIT_RINGS] rings evenly spaced in squared distance, so
## each covers the same area, over [code]T = FIT_REACH * max_r2[/code]: ring
## [code]k[/code] sits at the integer [code]t = (T * (2k + 1)) / (2 * FIT_RINGS)[/code]
## (integer division) and contributes its window [code]w[/code] at
## [code]sqrt(t) / 256[/code] and ramp [code]g[/code]. The energy is
## [code]sum(w g) / sum(w w)[/code], zero when every window is zero.
static func fit_energy(min_r2: int, max_r2: int, reach: float) -> float:
	var rings: Array[PackedFloat64Array] = _rings(min_r2, max_r2)
	var sums: PackedFloat64Array = _sums(rings[0], rings[1], reach)
	return sums[0] / sums[1] if sums[1] > 0.0 else 0.0


## The range scale of [constant Mode.FITTED_RANGE] for [param max_r2].
##
## Maximises [code]sum(w g)^2 / sum(w w)[/code] of [method fit_energy]'s rings,
## the share of the ramp the best energy explains, over scales of the edge in
## [[constant SCALE_LOW], [constant SCALE_HIGH]] by [constant SCALE_STEPS]
## golden-section steps, keeping the left probe on ties, and returns the
## final bracket's midpoint. The ramp's minimum is [method band_minimum], as
## gameplay keeps it, so the scale depends on the maximum only.
static func fitted_scale(max_r2: int) -> float:
	var rings: Array[PackedFloat64Array] = _rings(band_minimum(max_r2), max_r2)
	var base: float = edge_of(max_r2)
	var ratio: float = (sqrt(5.0) - 1.0) / 2.0
	var low: float = SCALE_LOW
	var high: float = SCALE_HIGH
	var left: float = high - ratio * (high - low)
	var right: float = low + ratio * (high - low)
	var left_score: float = _explained(rings, base * left)
	var right_score: float = _explained(rings, base * right)
	for _step: int in SCALE_STEPS:
		if left_score >= right_score:
			high = right
			right = left
			right_score = left_score
			left = high - ratio * (high - low)
			left_score = _explained(rings, base * left)
		else:
			low = left
			left = right
			left_score = right_score
			right = low + ratio * (high - low)
			right_score = _explained(rings, base * right)
	return (low + high) / 2.0


## The minimum squared radius gameplay keeps under [param max_r2]: the
## maximum less [constant BAND] in 32-bit unsigned arithmetic, or 1 when that
## underflows (EntityCaveLight).
static func band_minimum(max_r2: int) -> int:
	var minimum: int = (max_r2 - BAND) & UNSIGNED32
	return 1 if minimum > max_r2 else minimum


static func _explained(rings: Array[PackedFloat64Array], reach: float) -> float:
	var sums: PackedFloat64Array = _sums(rings[0], rings[1], reach)
	return sums[0] * sums[0] / sums[1] if sums[1] > 0.0 else 0.0


static func _rings(min_r2: int, max_r2: int) -> Array[PackedFloat64Array]:
	var total: int = FIT_REACH * max_r2
	var distances := PackedFloat64Array()
	var ramps := PackedFloat64Array()
	distances.resize(FIT_RINGS)
	ramps.resize(FIT_RINGS)
	for ring: int in FIT_RINGS:
		@warning_ignore("integer_division")
		var t: int = (total * (2 * ring + 1)) / (2 * FIT_RINGS)
		distances[ring] = sqrt(float(t)) / UNITS_PER_SQUARE
		ramps[ring] = ramp(t, min_r2, max_r2)
	return [distances, ramps]


static func _sums(distances: PackedFloat64Array, ramps: PackedFloat64Array, reach: float) -> PackedFloat64Array:
	var lit: float = 0.0
	var weight: float = 0.0
	if reach > 0.0:
		for ring: int in FIT_RINGS:
			var distance: float = distances[ring]
			if distance < reach:
				var ratio: float = distance / reach
				var quartic: float = ratio * ratio
				quartic = quartic * quartic
				var w: float = (1.0 - quartic) * (1.0 - quartic)
				lit += w * ramps[ring]
				weight += w * w
	return PackedFloat64Array([lit, weight])
