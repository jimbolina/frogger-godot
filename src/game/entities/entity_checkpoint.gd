class_name EntityCheckpoint
extends RefCounted
## Supported checkpoint update boundary before checkpoint collection is implemented.

## Rejects unsupported croak contact without advancing a candidate.
static func update(entity: EntitySnapshot, frog_position: Vector3i) -> String:
	var dx: int = frog_position.x - entity.matrix12[9]
	var dz: int = frog_position.z - entity.matrix12[11]
	if dx * dx + dz * dz <= 512 * 512:
		return "Checkpoint croak interaction is unsupported"
	return ""
