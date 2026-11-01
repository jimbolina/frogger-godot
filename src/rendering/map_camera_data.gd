class_name MapCameraData
extends RefCounted
## The map inspection camera's default pose, without gameplay following.

## Raw game positions and projection distance.
var source: Vector3i = Vector3i.ZERO
var target: Vector3i = Vector3i.ZERO
var projection_distance: int = 256


## The map's GENE camera offsets around the bounds midpoint.
static func for_scene(scene: MapSceneData) -> MapCameraData:
	var camera := MapCameraData.new()
	camera.source = scene.midpoint + scene.map.general.camera_source_offset
	camera.target = scene.midpoint + scene.map.general.camera_target_offset
	return camera


## Vertical field of view at the fixed 640 by 480 render size.
func vertical_fov() -> float:
	return rad_to_deg(2.0 * atan(240.0 / float(projection_distance)))


## Godot source position, converting only at the presentation boundary.
func position() -> Vector3:
	return GameSpace.position(source.x, source.y, source.z)


## Godot target position.
func look_target() -> Vector3:
	return GameSpace.position(target.x, target.y, target.z)
