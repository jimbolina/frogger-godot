extends SceneTree
## Measures how the renderer turns scene lighting into screen bytes.
##
## Lights a scene through [SceneLighting], with the live graphics profile's
## bloom and tone mapping, from [method SceneLightingBuilder.from_lighting] on
## synthetic [MapLighting] records, draws a lit quad with a minimal Lambert material, reads back the
## centre pixel and compares it with the byte the lighting recipe asks for.
## The lit case yields the renderer's direct light per unit energy, whose
## reciprocal is the [constant SceneLightingBuilder.LAMBERT_SCALE] that makes
## the lit face match. A second lit case faces the light source: its inward
## normal, as the source models store them, equals the stored C direction,
## the side [method MapLighting.shade] lights fully, which checks the sign.
## It needs a real window, so it is not part of the test run:
##
##   godot --path . --script tools/probe_scene_lighting.gd -- --output=<folder>
##
## The folder must be absolute and outside the repository. The report goes to
## [code]scene_lighting_<method>.txt[/code] there and to the log.

## Albedo byte of every quad.
const ALBEDO: int = 128
## Stored ambient of every case, 73 times 16.
const AMBIENT: float = 73.0 * 16.0
## Stored colour of the white parallel light, 255 times 16.
const PARALLEL: float = 255.0 * 16.0
## How far the measured byte may be from the expected one.
const TOLERANCE: int = 1
## Frames drawn before reading the screen back.
const SETTLE_FRAMES: int = 4
## The minimal lit material: Lambert diffuse plus the ambient as emission.
const SHADER: String = """shader_type spatial;
render_mode diffuse_lambert, specular_disabled, ambient_light_disabled;

uniform vec3 albedo_colour : source_color;
uniform vec3 ambient_global;

void fragment() {
	ALBEDO = albedo_colour;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	EMISSION = ALBEDO * ambient_global;
}
"""


## One measured configuration: its lighting, the quad normal facing the camera
## and whether it measures the scale against the built lights instead of C.
class Case:
	extends RefCounted
	var label: String
	var lighting: MapLighting
	var normal: Vector3
	var measures_scale: bool

	func _init(case_label: String, case_lighting: MapLighting, case_normal: Vector3,
			case_measures_scale: bool) -> void:
		label = case_label
		lighting = case_lighting
		normal = case_normal
		measures_scale = case_measures_scale


var _scene: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var folder: String = ViewerArguments.value(OS.get_cmdline_user_args(), "--output=")
	var issue: String = ViewerCapture.prepare_folder(folder)
	if not issue.is_empty():
		push_error(issue)
		quit(2)
		return
	var lit := MapLighting.new()
	lit.ambient = Vector3(AMBIENT, AMBIENT, AMBIENT)
	lit.directions.append(Vector3.DOWN)
	lit.colours.append(Vector3(PARALLEL, PARALLEL, PARALLEL))
	var ambient_only := MapLighting.new()
	ambient_only.ambient = Vector3(AMBIENT, AMBIENT, AMBIENT)
	var godot_facing: Vector3 = SceneLightingBuilder.from_lighting(lit, false).lights[0].basis.z
	var cases: Array[Case] = [
		Case.new("lit, facing the Godot light", lit, godot_facing, true),
		Case.new("lit, inward normal along the stored C direction", lit, -lit.directions[0], false),
		Case.new("ambient only", ambient_only, Vector3.UP, false),
	]
	var method: String = RenderingServer.get_current_rendering_method()
	var lines := PackedStringArray()
	lines.append("rendering method: %s" % method)
	lines.append("video adapter: %s" % RenderingServer.get_video_adapter_name())
	lines.append("albedo byte: %d, stored ambient: %d, stored parallel: %d" % [ALBEDO, int(AMBIENT), int(PARALLEL)])
	lines.append("LAMBERT_SCALE in use: %s" % SceneLightingBuilder.LAMBERT_SCALE)
	var settings: GraphicsSettings = GraphicsProfile.current()
	lines.append("bloom: %s, intensity %s, threshold %s; tone mapper %d, exposure %s" % [
		settings.bloom, settings.bloom_intensity, settings.bloom_threshold, settings.tonemapper, settings.exposure])
	var failures: int = 0
	for item: Case in cases:
		var spec: SceneLightingSpec = SceneLightingBuilder.from_lighting(item.lighting, false)
		_build(spec, item.normal)
		for _frame: int in SETTLE_FRAMES:
			await process_frame
		await RenderingServer.frame_post_draw
		var screen: Image = root.get_texture().get_image()
		var measured: Color = screen.get_pixel(floori(screen.get_width() / 2.0), floori(screen.get_height() / 2.0))
		var albedo: float = Color8(ALBEDO, ALBEDO, ALBEDO).srgb_to_linear().r
		var direct: float = _direct(spec, item.normal)
		var expected_linear: float = albedo * _c_total(item.lighting, item.normal)
		if item.measures_scale:
			expected_linear = albedo * (spec.ambient.x + direct / SceneLightingBuilder.LAMBERT_SCALE)
		var expected: int = _byte(expected_linear)
		var ok: bool = absi(measured.r8 - expected) <= TOLERANCE
		if not ok:
			failures += 1
		lines.append("%s  %s: expected %d, measured (%d, %d, %d), Godot light facing %.4f, C facing %.4f" % [
			"ok  " if ok else "FAIL", item.label, expected, measured.r8, measured.g8, measured.b8,
			_facing(spec, item.normal), _c_facing(item.lighting, item.normal)])
		if item.measures_scale:
			var measured_direct: float = measured.srgb_to_linear().r / albedo - spec.ambient.x
			var per_energy: float = measured_direct / direct if direct > 0.0 else 0.0
			lines.append("      measured/expected linear: %.4f" % (measured.srgb_to_linear().r / expected_linear))
			lines.append("      direct light per unit energy: %.4f" % per_energy)
			if per_energy > 0.0:
				lines.append("      LAMBERT_SCALE for an exact lit face: %.4f" % (SceneLightingBuilder.LAMBERT_SCALE / per_energy))
			if measured.r8 >= 255:
				lines.append("      the lit face saturates; the ratio is a lower bound")
	lines.append("%d of %d as expected (within %d)" % [cases.size() - failures, cases.size(), TOLERANCE])
	var report: String = "\n".join(lines)
	print(report)
	var path: String = folder.path_join("scene_lighting_%s.txt" % method)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write report '%s': %s" % [path, error_string(FileAccess.get_open_error())])
		quit(2)
		return
	file.store_string(report + "\n")
	file.close()
	quit(1 if failures > 0 else 0)


func _build(spec: SceneLightingSpec, normal: Vector3) -> void:
	if _scene != null:
		root.remove_child(_scene)
		_scene.free()
	_scene = Node3D.new()
	root.add_child(_scene)
	var lighting := SceneLighting.new()
	_scene.add_child(lighting)
	lighting.apply(spec)
	var shader := Shader.new()
	shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_colour", Color8(ALBEDO, ALBEDO, ALBEDO))
	material.set_shader_parameter("ambient_global", spec.ambient)
	var quad := QuadMesh.new()
	quad.size = Vector2(4.0, 4.0)
	var face := MeshInstance3D.new()
	face.mesh = quad
	face.material_override = material
	face.transform = Transform3D(_facing_basis(normal), Vector3.ZERO)
	_scene.add_child(face)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.0
	camera.transform = Transform3D(_facing_basis(normal), normal * 2.0)
	_scene.add_child(camera)
	camera.make_current()


func _facing_basis(normal: Vector3) -> Basis:
	var up: Vector3 = Vector3.FORWARD if absf(normal.y) > 0.999 else Vector3.UP
	return Basis.looking_at(-normal, up)


func _facing(spec: SceneLightingSpec, normal: Vector3) -> float:
	var best: float = 0.0
	for light: SceneLightingSpec.Light in spec.lights:
		best = maxf(best, normal.dot(light.basis.z))
	return best


func _c_facing(lighting: MapLighting, normal: Vector3) -> float:
	var best: float = 0.0
	for direction: Vector3 in lighting.directions:
		best = maxf(best, direction.dot(-normal))
	return best


func _c_total(lighting: MapLighting, normal: Vector3) -> float:
	var stored: float = lighting.ambient.x
	for index: int in lighting.directions.size():
		stored += lighting.colours[index].x * maxf(0.0, lighting.directions[index].dot(-normal))
	return pow(clampf(stored / SceneLightingBuilder.STORED_ONE, 0.0, 1.0), SceneLightingBuilder.GAMMA)


func _direct(spec: SceneLightingSpec, normal: Vector3) -> float:
	var total: float = 0.0
	for light: SceneLightingSpec.Light in spec.lights:
		var colour: float = light.colour.srgb_to_linear().r
		total += light.energy * colour * maxf(0.0, normal.dot(light.basis.z))
	return total


func _byte(linear: float) -> int:
	var value: float = clampf(linear, 0.0, 1.0)
	return roundi(Color(value, value, value).linear_to_srgb().r * 255.0)
