class_name GlowLightPool
extends Node3D
## A pool of up to [constant MAX_LIGHTS] small shadowless [OmniLight3D]s placed at glow points.
##
## Lights are created the first time that many are needed and kept; each
## [method place] reuses them in order and hides the rest, so steady drawing
## creates and frees nothing.

## Largest number of glow lights.
const MAX_LIGHTS: int = 16
## Distance attenuation exponent of each light.
const ATTENUATION: float = 1.0

var _lights: Array[OmniLight3D] = []


## Shows one light per point of [param points], up to [constant MAX_LIGHTS],
## at the point's energy times [param energy_scale]; hides the rest and
## returns the number shown.
func place(points: Array[GlowLightSpec.Point], energy_scale: float = 1.0) -> int:
	var shown: int = mini(points.size(), MAX_LIGHTS)
	while _lights.size() < shown:
		_lights.append(_light())
	for index: int in _lights.size():
		var light: OmniLight3D = _lights[index]
		if index >= shown:
			light.visible = false
			continue
		var point: GlowLightSpec.Point = points[index]
		light.position = point.position
		light.light_color = point.colour
		light.light_energy = point.energy * energy_scale
		light.omni_range = point.radius
		light.visible = true
	return shown


## Hides every light.
func hide_all() -> void:
	for light: OmniLight3D in _lights:
		light.visible = false


## The pooled lights, shown or hidden.
func lights() -> Array[OmniLight3D]:
	return _lights.duplicate()


## The number of lights currently shown.
func shown_count() -> int:
	var count: int = 0
	for light: OmniLight3D in _lights:
		if light.visible:
			count += 1
	return count


func _light() -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "GlowLight%d" % _lights.size()
	light.shadow_enabled = false
	light.light_specular = 0.0
	light.omni_attenuation = ATTENUATION
	light.visible = false
	add_child(light)
	return light
