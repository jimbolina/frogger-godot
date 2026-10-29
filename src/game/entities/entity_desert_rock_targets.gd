class_name EntityDesertRockTargets
extends RefCounted
## Frozen ENTSTRDesCreateFallingRock projection of authored bounce targets onto the landscape.

## Source fr_target lift applied to the first target only.
const FIRST_TARGET_LIFT: int = 0x80

## Every input target, with the first bounce count projected; empty when error is set.
var targets: Array[Vector3i] = []
## Why projection failed, or "".
var error: String = ""

## Snaps each used target's X and Z to its cell centre, takes Y from GetHeightFromWorldXYZ with the
## authored Y selecting the layer, and lifts target 0 by 0x80: the source while(i--) loop reaches
## i == bounces - 1 on its first pass. Values narrow to signed shorts; unused targets are unchanged.
static func resolve(authored: Array[Vector3i], grid: GridDefinition, bounces: int) -> EntityDesertRockTargets:
	var result := EntityDesertRockTargets.new()
	if grid == null:
		result.error = "Falling rock targets require terrain"
		return result
	if bounces < 1 or bounces > authored.size():
		result.error = "Falling rock requires 1 to %d bounce targets, got %d" % [authored.size(), bounces]
		return result
	var resolved: Array[Vector3i] = authored.duplicate()
	for index: int in bounces:
		var target: Vector3i = authored[index]
		var x: int = PlatformMath.s16((target.x & ~0xff) + 0x80)
		var z: int = PlatformMath.s16((target.z & ~0xff) + 0x80)
		var surface: GridSurfaceInfo = GridQueries.height_at(grid, x, target.y, z)
		if surface == null:
			result.error = "Falling rock target %d at (%d, %d) has no terrain stack" % [index, x, z]
			return result
		var y: int = PlatformMath.s16(surface.height)
		if index == 0:
			y = PlatformMath.s16(y - FIRST_TARGET_LIFT)
		resolved[index] = Vector3i(x, y, z)
	result.targets = resolved
	return result
