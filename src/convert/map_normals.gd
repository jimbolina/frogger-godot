class_name MapNormals
extends RefCounted
## Per-corner Godot normals of map polygons, for the modern profile's lights.
##
## The builder emits each polygon's triangles in strip order
## ([method MapMeshBuilder.triangle_corners]), and Godot shows a triangle's front
## when its corners run clockwise on screen, so the normal facing a camera that
## sees the front is [code](c - a).cross(b - a)[/code]; a floor seen from above
## gets [constant Vector3.UP]. A quad's normal sums its two triangles. Flat
## polygon types use their face normal on every corner. Gouraud types average,
## per source vertex, the face normals of every polygon sharing that vertex whose
## normal lies within [constant CREASE_DEGREES] of their own, so a floor meeting
## a wall keeps a hard crease. Lines and degenerate faces point up.

## Gouraud polygon types: G3, G4, GT3 and GT4.
const GOURAUD_TYPES: Array[int] = [4, 5, 6, 7]
## The line type, G2, which has no face.
const LINE_TYPE: int = 8
## Largest angle between two faces whose normals still blend at a shared vertex.
const CREASE_DEGREES: float = 60.0

var _polygons: Array[MapPolygon] = []
var _faces := PackedVector3Array()
var _incident: Dictionary[int, PackedInt32Array] = {}
var _crease_cosine: float = cos(deg_to_rad(CREASE_DEGREES))


## Computes every polygon's face normal and the polygons around each vertex.
func configure(vertices: Array[Vector3i], polygons: Array[MapPolygon]) -> void:
	_polygons = polygons
	_faces.clear()
	_incident.clear()
	for index: int in polygons.size():
		var polygon: MapPolygon = polygons[index]
		var points := PackedVector3Array()
		for vertex_index: int in polygon.vertex_indices:
			var raw: Vector3i = vertices[vertex_index]
			points.append(GameSpace.position(raw.x, raw.y, raw.z))
		_faces.append(Vector3.UP if polygon.type_index == LINE_TYPE else face_normal(points))
		if polygon.type_index == LINE_TYPE:
			continue
		for vertex_index: int in polygon.vertex_indices:
			var around: PackedInt32Array = _incident.get(vertex_index, PackedInt32Array())
			if not around.has(index):
				around.append(index)
				_incident[vertex_index] = around


## The unit normal facing a camera that sees the front of the polygon whose
## Godot corner positions are [param points], in stored (strip) order.
static func face_normal(points: PackedVector3Array) -> Vector3:
	if points.size() < 3:
		return Vector3.UP
	var corners: PackedInt32Array = MapMeshBuilder.triangle_corners(points.size())
	var sum := Vector3.ZERO
	for start: int in range(0, corners.size(), 3):
		var a: Vector3 = points[corners[start]]
		var b: Vector3 = points[corners[start + 1]]
		var c: Vector3 = points[corners[start + 2]]
		sum += (c - a).cross(b - a)
	return sum.normalized() if not sum.is_zero_approx() else Vector3.UP


## The face normal of polygon [param polygon_index].
func face(polygon_index: int) -> Vector3:
	return _faces[polygon_index]


## The normal at stored corner [param corner] of polygon [param polygon_index].
func corner_normal(polygon_index: int, corner: int) -> Vector3:
	var own: Vector3 = _faces[polygon_index]
	var polygon: MapPolygon = _polygons[polygon_index]
	if not GOURAUD_TYPES.has(polygon.type_index):
		return own
	var sum := Vector3.ZERO
	for other: int in _incident.get(polygon.vertex_indices[corner], PackedInt32Array()):
		var normal: Vector3 = _faces[other]
		if own.dot(normal) >= _crease_cosine - 0.000001:
			sum += normal
	return sum.normalized() if not sum.is_zero_approx() else own
