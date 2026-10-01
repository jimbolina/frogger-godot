class_name MapWaterState
extends RefCounted
## Instance-local WATER.C vertex wibble, with source-space integer positions.
## C's coordinate sort is commented out: retain FT4 then GT4 encounter order.

var tick: int = -1
var enabled: bool = true
var water_height: int = 1000
var vertex_indices := PackedInt32Array()
var _original: Array[Vector3i] = []
var _current: Array[Vector3i] = []
var _table := PackedInt32Array()
var _offsets := PackedVector2Array()


## Selects unique submerged MAX_OT FT4/GT4 vertices, using first ENVMAP FT4
## as water height. More than two players disables the original water effect.
func configure(source_vertices: Array[Vector3i], polygons: Array[MapPolygon], players: int = 1) -> void:
	_original = source_vertices.duplicate()
	vertex_indices.clear()
	water_height = 1000
	for polygon: MapPolygon in polygons:
		if polygon.type_index == 3 and (polygon.flags & 2) and not polygon.vertex_indices.is_empty():
			water_height = source_vertices[polygon.vertex_indices[0]].y
			break
	var seen: Dictionary[int, bool] = {}
	if players <= 2:
		for type_index: int in [3, 7]:
			for polygon: MapPolygon in polygons:
				if polygon.type_index != type_index or not (polygon.flags & 4):
					continue
				for index: int in polygon.vertex_indices:
					if seen.has(index) or index < 0 or index >= source_vertices.size():
						continue
					seen[index] = true
					if source_vertices[index].y > water_height + 50:
						vertex_indices.append(index)
	_table.clear()
	var previous: int = 0
	for index: int in 32:
		# Frozen portable engine synthesizes rsin by lround(sin * 4096).
		var current: int = roundi(sin(float(index + 1) * TAU / 32.0) * 4096.0) >> 9
		_table.append(current - previous)
		previous = current
	reset()


## Restores geometry and the deterministic session clock.
func reset() -> void:
	tick = -1
	_current = _original.duplicate()
	_offsets.resize(32)
	_offsets.fill(Vector2.ZERO)


## Applies this tick's differential sine/cosine displacement, narrowing shorts.
## Disable for map-slice reference mode; the clock still advances.
func step() -> void:
	tick += 1
	if not enabled:
		return
	var count: int = _short(tick)
	var phase: int = count >> 1
	for rank: int in 32:
		_offsets[rank] += Vector2(_table[(phase + rank) & 31], _table[(phase + rank + 8) & 31])
	for index: int in vertex_indices:
		var point: Vector3i = _current[index]
		point.x = _short(point.x + _table[phase & 31])
		point.z = _short(point.z + _table[(phase + 8) & 31])
		_current[index] = point
		phase += 1


## Restarts and replays to the requested tick; zero includes one update.
func seek(to_tick: int) -> void:
	reset()
	for _index: int in maxi(0, to_tick + 1):
		step()


## Returns a detached snapshot in original game units.
func vertices() -> Array[Vector3i]:
	return _current.duplicate()


## Cumulative X/Z offsets for the 32 repeating encounter phases. Shaders can
## use each selected vertex's encounter rank modulo32 without mesh rebuilds.
func phase_offsets() -> PackedVector2Array:
	return _offsets.duplicate()


static func _short(value: int) -> int:
	return ((value + 32768) & 65535) - 32768
