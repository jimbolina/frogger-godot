class_name MapLighting
extends RefCounted
## Instance-local model lighting, separate from the cave terrain grey ramp.
## Inputs and output colours use stored RGB values, not linear light.

var ambient := Vector3.ZERO
var directions: Array[Vector3] = []
var colours: Array[Vector3] = []


## Builds the C viewport's ambient and three parallel-light slots.
## MRAddObjectToViewport prepends lights, so later map records win slots.
func configure(lights: Array[MapLight]) -> void:
	ambient = Vector3.ZERO
	directions.clear()
	colours.clear()
	for index: int in range(lights.size() - 1, -1, -1):
		var light: MapLight = lights[index]
		if not light.enabled:
			continue
		var rgb := Vector3(light.color.r8, light.color.g8, light.color.b8)
		if light.light_type == 1:
			ambient += rgb * 16.0
		elif light.light_type == 2 and directions.size() < 3:
			var direction := Vector3(light.direction)
			var length: float = direction.length()
			var fixed_direction := Vector3i.ZERO
			if length > 0.0:
				fixed_direction = Vector3i(roundi(direction.x * 4096.0 / length),
					roundi(direction.y * 4096.0 / length), roundi(direction.z * 4096.0 / length))
			directions.append(GameSpace.normal(fixed_direction.x, fixed_direction.y, fixed_direction.z))
			colours.append(rgb * 16.0)
	ambient = Vector3((int(ambient.x) >> 4) & 255,
		(int(ambient.y) >> 4) & 255, (int(ambient.z) >> 4) & 255) * 16.0


## Shades a model normal transformed into world space. Flat faces call once;
## Gouraud faces call for each corner. C transforms normals without rescaling.
func shade(base: Color, normal: Vector3, world_basis: Basis = Basis.IDENTITY) -> Color:
	var world_normal: Vector3 = world_basis * normal
	var illumination: Vector3 = ambient
	for index: int in directions.size():
		illumination += colours[index] * maxf(0.0, directions[index].dot(world_normal))
	var rgb := Vector3(base.r8, base.g8, base.b8) * illumination / 4096.0
	return Color(float(clampi(int(rgb.x), 0, 255)) / 255.0,
		float(clampi(int(rgb.y), 0, 255)) / 255.0,
		float(clampi(int(rgb.z), 0, 255)) / 255.0, base.a)


## Frozen mapdisp.c replaces terrain Gouraud colours with distance grey.
## Positions and squared radii are in game units. Difference narrows to SVEC.
static func cave_colour(vertex: Vector3i, frog: Vector3i, minimum_r2: int, maximum_r2: int) -> Color:
	var difference := vertex - frog
	difference = Vector3i(_short(difference.x), _short(difference.y), _short(difference.z))
	var distance: int = difference.x * difference.x + difference.y * difference.y + difference.z * difference.z
	var grey: int = cave_intensity(distance, minimum_r2, maximum_r2)
	return Color(float(grey) / 255.0, float(grey) / 255.0, float(grey) / 255.0)


## Integer grey byte at a squared distance; equal radii use a hard cutoff.
static func cave_intensity(distance: int, minimum_r2: int, maximum_r2: int) -> int:
	var grey: int = 128
	if distance > maximum_r2:
		grey = 0
	elif distance >= minimum_r2 and maximum_r2 > minimum_r2:
		@warning_ignore("integer_division")
		var factor: int = (128 << 16) / (maximum_r2 - minimum_r2)
		grey = 128 - ((factor * (distance - minimum_r2)) >> 16)
	return clampi(grey, 0, 128)


## Initial terrain radii established by ENTSTRCavCreateFroggerLight.
static func initial_cave_radii(maximum_radius: int) -> PackedInt64Array:
	var maximum_r2: int = ((maximum_radius << 8) * (maximum_radius << 8)) & 0xffffffff
	var minimum_r2: int = (maximum_r2 - 0x100000) & 0xffffffff
	return PackedInt64Array([1 if minimum_r2 > maximum_r2 else minimum_r2, maximum_r2])


static func _short(value: int) -> int:
	return ((value + 32768) & 65535) - 32768
