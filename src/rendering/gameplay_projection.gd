class_name GameplayProjection
extends RefCounted
## Frozen Windows gameplay camera projection supplied to presentation adapters.

const PERSPECTIVE_H: int = 256
const ASPECT_WIDTH: int = 320
const ASPECT_HEIGHT: int = 256

## Converts the retained source camera basis and translation, including shake.
static func camera_transform(snapshot: GameplayCameraSnapshot) -> Transform3D:
	var x: Vector3i = snapshot.axis_x_12
	var y: Vector3i = snapshot.axis_y_12
	var z: Vector3i = snapshot.axis_z_12
	var at: Vector3i = snapshot.source_world
	return GameSpace.transform(PackedInt32Array([x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z, at.x, at.y, at.z]))

## Vertical FOV for a symmetric native camera whose focal X matches source H.
static func vertical_fov_degrees(viewport_size: Vector2i) -> float:
	var focal_x: float = float(PERSPECTIVE_H) * viewport_size.x / ASPECT_WIDTH
	return rad_to_deg(2.0 * atan(float(viewport_size.y) / (2.0 * focal_x)))

## Shader clip scaling supplies the source's unequal vertical focal distance.
static func clip_scale(viewport_size: Vector2i) -> Vector2:
	return Vector2(1.0, float(viewport_size.y * ASPECT_WIDTH) / float(viewport_size.x * ASPECT_HEIGHT))
