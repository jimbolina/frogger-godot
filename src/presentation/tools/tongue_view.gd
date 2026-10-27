class_name TongueView
extends MeshInstance3D
## Inspection ribbon built from committed source tongue sections without advancing effects.

var _ribbon := ImmediateMesh.new()
var _material: ShaderMaterial
var _tick: int = -1
var _state: TongueState

## Rebuilds the small ribbon only when the committed effect sample changes.
func draw_state(state: GameplayState) -> void:
	if _tick == state.tick_index and _state == state.tongue:
		return
	_tick = state.tick_index
	_state = state.tongue
	visible = _state.mode != TongueState.Mode.IDLE and _state.section > 0
	_ribbon.clear_surfaces()
	if not visible:
		return
	if _material == null:
		_material = ModelShaders.material(null, ModelShaders.Blend.ADD, false, true)
	mesh = _ribbon
	var points: Array[Vector3] = []
	for section: int in 9:
		var point: Vector3i = TongueCurve.tip(state.frog.matrix12, section, _state.curve_target, _state.curve_has_target)
		points.append(GameSpace.position(point.x, point.y, point.z))
	var up: Vector3 = GameSpace.normal(state.frog.matrix12[1], state.frog.matrix12[4], state.frog.matrix12[7])
	var sides: Array[Vector3] = []
	for section: int in _state.section + 1:
		var tangent: Vector3 = points[mini(section + 1, 8)] - points[maxi(section - 1, 0)]
		var side: Vector3 = up.cross(tangent).normalized() * (16.0 / GameSpace.UNITS_PER_SQUARE)
		sides.append(side)
	_ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	var centre := Color(160.0 / 255.0, 32.0 / 255.0, 0.0)
	for section: int in _state.section:
		for sign_value: float in [-1.0, 1.0]:
			var a: Vector3 = points[section]
			var b: Vector3 = points[section + 1]
			var c: Vector3 = a + sides[section] * sign_value
			var d: Vector3 = b + sides[section + 1] * sign_value
			_vertex(a, centre)
			_vertex(b, centre)
			_vertex(c, Color.BLACK)
			_vertex(c, Color.BLACK)
			_vertex(b, centre)
			_vertex(d, Color.BLACK)
	_ribbon.surface_end()

func _vertex(point: Vector3, colour: Color) -> void:
	_ribbon.surface_set_color(colour)
	_ribbon.surface_add_vertex(point)
