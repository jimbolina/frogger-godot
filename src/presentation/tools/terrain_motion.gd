class_name TerrainMotion
extends RefCounted
## Converts committed samples once per tick and interpolates presentation only.

var _before_frog: Transform3D = Transform3D.IDENTITY
var _frog: Transform3D = Transform3D.IDENTITY
var _before_camera: Transform3D = Transform3D.IDENTITY
var _camera: Transform3D = Transform3D.IDENTITY
var _before_entities: Array[Transform3D] = []
var _entities: Array[Transform3D] = []
var _attached_slot: int = -1
var _before_local_frog: Transform3D
var _local_frog: Transform3D

## Supplies detached viewer snapshots; only converted values are retained.
func capture(previous: RunSnapshot, current: RunSnapshot) -> void:
	_before_frog = GameSpace.transform(previous.frog.matrix12)
	_before_frog.origin = GameSpace.fixed_position(previous.frog.position_16)
	_frog = GameSpace.transform(current.frog.matrix12)
	_frog.origin = GameSpace.fixed_position(current.frog.position_16)
	_before_camera = GameplayProjection.camera_transform(previous.camera) if previous.camera != null else Transform3D.IDENTITY
	_camera = GameplayProjection.camera_transform(current.camera) if current.camera != null else _before_camera
	_before_entities.clear()
	_entities.clear()
	_attached_slot = -1
	if current.entities == null:
		return
	for slot: int in current.entities.entities.size():
		var now: EntitySnapshot = current.entities.entities[slot]
		var before: EntitySnapshot = previous.entities.entities[slot] if previous.entities != null and slot < previous.entities.entities.size() else null
		var transform_now: Transform3D = GameSpace.transform(now.matrix12)
		var continuous: bool = before != null and before.entity_index == now.entity_index and before.unique_id == now.unique_id and before.generation == now.generation and before.live and now.live
		if continuous and before.background != null and now.background != null:
			continuous = before.background.carrier_index == now.background.carrier_index and before.background.parent_entity_index == now.background.parent_entity_index
		var transform_before: Transform3D = GameSpace.transform(before.matrix12) if continuous else transform_now
		_entities.append(transform_now)
		_before_entities.append(transform_before)
		if not continuous and now.entity_index == previous.attachment.current_entity_index and now.entity_index == current.attachment.current_entity_index:
			_before_frog = _frog
			_before_camera = _camera
		if continuous and now.entity_index == previous.attachment.current_entity_index and now.entity_index == current.attachment.current_entity_index and absf(transform_before.basis.determinant()) > 0.000001 and absf(transform_now.basis.determinant()) > 0.000001:
			_attached_slot = slot
			_before_local_frog = transform_before.affine_inverse() * _before_frog
			_local_frog = transform_now.affine_inverse() * _frog

## Interpolates a carried frog in the same moving frame as its platform.
func frog(fraction: float) -> Transform3D:
	var weight: float = clampf(fraction, 0.0, 1.0)
	if weight <= 0.0:
		return _before_frog
	if weight >= 1.0:
		return _frog
	if _attached_slot >= 0:
		return entity(_attached_slot, weight) * blend(_before_local_frog, _local_frog, weight)
	return blend(_before_frog, _frog, weight)

## Interpolates the retained source camera basis and translation.
func camera(fraction: float) -> Transform3D:
	return blend(_before_camera, _camera, fraction)

## A newly created generation starts with collapsed history.
func entity(slot: int, fraction: float) -> Transform3D:
	return blend(_before_entities[slot], _entities[slot], fraction)

## Keeps exact endpoints and handles singular scales without quaternion decomposition.
static func blend(before: Transform3D, current: Transform3D, fraction: float) -> Transform3D:
	var weight: float = clampf(fraction, 0.0, 1.0)
	if weight <= 0.0 or before == current:
		return before
	if weight >= 1.0:
		return current
	if absf(before.basis.determinant()) < 0.000001 or absf(current.basis.determinant()) < 0.000001:
		return Transform3D(Basis(before.basis.x.lerp(current.basis.x, weight), before.basis.y.lerp(current.basis.y, weight), before.basis.z.lerp(current.basis.z, weight)), before.origin.lerp(current.origin, weight))
	return before.interpolate_with(current, weight)
