class_name GlowLightSpec
extends RefCounted
## The small coloured lights placed at glowing sprites, as node-free points.
##
## Each glow gives one point at its centre, lifted by [constant LIFT], in the
## halo's colour on the light's scale (the sprite colour doubled and clamped).
## Its energy follows the [GlowPulse] magnitude, peaking at [constant ENERGY]
## when the halo is largest, so the light pulses with it. Positions and ranges
## are Godot units: one grid square is one unit.

## Light range in grid squares.
const RANGE_SQUARES: float = 1.5
## Energy at the largest pulse.
const ENERGY: float = 0.75
## Height of the light above the glow's centre.
const LIFT: float = 0.0
## Pulse angle of the largest sine, a quarter turn.
const PEAK_ANGLE: int = 0x400

## One glow light: Godot position, colour, energy and range (radius).
class Point extends RefCounted:
	var position := Vector3.ZERO
	var colour := Color.WHITE
	var energy: float = 0.0
	var radius: float = 0.0

	func _init(at: Vector3 = Vector3.ZERO, light_colour: Color = Color.WHITE, light_energy: float = 0.0, light_range: float = 0.0) -> void:
		position = at
		colour = light_colour
		energy = light_energy
		radius = light_range


## The sprite colour of a pickup table glow colour stored as 0x00BBGGRR.
static func colour_of(glow_colour_bgr: int) -> Color:
	return Color((glow_colour_bgr & 255) / 255.0, ((glow_colour_bgr >> 8) & 255) / 255.0, ((glow_colour_bgr >> 16) & 255) / 255.0)


## The light colour of sprite colour [param sprite_colour]: doubled and clamped, as the halo draws it.
static func light_colour(sprite_colour: Color) -> Color:
	return Color(minf(sprite_colour.r * 2.0, 1.0), minf(sprite_colour.g * 2.0, 1.0), minf(sprite_colour.b * 2.0, 1.0))


## Energy ratio of 16.16 glow [param magnitude] to the largest pulse magnitude.
static func energy_ratio(magnitude: int) -> float:
	return float(magnitude) / float(GlowPulse.magnitude(PEAK_ANGLE))


## The light of a glow at Godot [param at] in sprite colour [param sprite_colour] and pulse [param magnitude].
static func point(at: Vector3, sprite_colour: Color, magnitude: int) -> Point:
	return Point.new(at + Vector3.UP * LIFT, light_colour(sprite_colour), ENERGY * energy_ratio(magnitude), RANGE_SQUARES)


## Up to [param cap] of [param points] nearest [param camera_position],
## nearest first; equal distances keep their supplied order.
static func nearest(points: Array[Point], camera_position: Vector3, cap: int) -> Array[Point]:
	var order: Array[int] = []
	var distances := PackedFloat64Array()
	for index: int in points.size():
		order.append(index)
		distances.append(points[index].position.distance_squared_to(camera_position))
	order.sort_custom(func(a: int, b: int) -> bool: return distances[a] < distances[b] or (distances[a] == distances[b] and a < b))
	var chosen: Array[Point] = []
	for index: int in mini(maxi(cap, 0), order.size()):
		chosen.append(points[order[index]])
	return chosen
