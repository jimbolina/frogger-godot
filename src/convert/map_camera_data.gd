class_name MapCameraData
extends RefCounted
## Static map inspection camera presets, without gameplay following.

## Raw game positions and projection distance.
var source: Vector3i = Vector3i.ZERO
var target: Vector3i = Vector3i.ZERO
var projection_distance: int = 256
## Frozen reference viewport doubles X; shader clip scaling supplies PAL Y.
var projection_scale: int = 1
## Exact frozen translation unit uses PAL Y aspect480/256 against X640/320.
var vertical_ratio: float = 1.0

## Default offsets orbit the bounds midpoint. Reference matches frozen map_slice.
static func for_scene(scene: MapSceneData, preset: String = "default") -> MapCameraData:
	var camera := MapCameraData.new()
	camera.target = scene.midpoint
	if preset == "map-slice":
		camera.source = scene.midpoint + Vector3i(0, -10000, -10000)
		camera.projection_distance = 1000
		camera.projection_scale = 2
		camera.vertical_ratio = 0.9375
	else:
		camera.source = scene.midpoint + scene.map.general.camera_source_offset
		camera.target += scene.map.general.camera_target_offset
	return camera

## Vertical field of view at the fixed 640 by 480 render size.
func vertical_fov() -> float:
	return rad_to_deg(2.0 * atan(240.0 / float(projection_distance * projection_scale)))

## Godot source position, converting only at the presentation boundary.
func position() -> Vector3:
	return GameSpace.position(source.x, source.y, source.z)

## Godot target position.
func look_target() -> Vector3:
	return GameSpace.position(target.x, target.y, target.z)
