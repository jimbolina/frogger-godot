class_name EmissiveLightSet
extends Node3D
## One soft shadowless [OmniLight3D] over each [EmissiveClusters.Cluster] of glowing lava.
##
## Lights are created when more clusters arrive than there are lights and
## kept; surplus lights are hidden. Changing only the energy scale or the
## switch updates the existing lights. Each light fades out with camera
## distance between [constant FADE_BEGIN] and [constant FADE_BEGIN] plus
## [constant FADE_LENGTH].

## Distance attenuation exponent of each light; below 1 spreads the light
## further across its range before the edge.
const ATTENUATION: float = 0.25
## Specular share of each light.
const SPECULAR: float = 0.0
## Camera distance at which a light starts to fade, in grid squares.
const FADE_BEGIN: float = 40.0
## Distance over which a light fades out, in grid squares.
const FADE_LENGTH: float = 10.0

var _lights: Array[OmniLight3D] = []


## Shows one light per cluster of [param clusters] at the cluster's energy
## times [param energy_scale], or hides every light when [param enabled] is
## false; returns the number shown.
func set_clusters(clusters: Array[EmissiveClusters.Cluster], energy_scale: float = 1.0, enabled: bool = true) -> int:
	while enabled and _lights.size() < clusters.size():
		_lights.append(_light())
	var shown: int = 0
	for index: int in _lights.size():
		var light: OmniLight3D = _lights[index]
		if index >= clusters.size() or not enabled:
			light.visible = false
			continue
		var cluster: EmissiveClusters.Cluster = clusters[index]
		light.position = cluster.centre
		light.omni_range = cluster.radius
		light.light_color = cluster.colour
		light.light_energy = cluster.energy * energy_scale
		light.visible = true
		shown += 1
	return shown


## The lights, shown or hidden.
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
	light.name = "LavaLight%d" % _lights.size()
	light.shadow_enabled = false
	light.light_specular = SPECULAR
	light.omni_attenuation = ATTENUATION
	light.distance_fade_enabled = true
	light.distance_fade_begin = FADE_BEGIN
	light.distance_fade_length = FADE_LENGTH
	light.visible = false
	add_child(light)
	return light
