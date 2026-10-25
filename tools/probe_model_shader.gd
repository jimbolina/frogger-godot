extends SceneTree
## Measures what the model shaders put on screen, pixel by pixel.
##
## Draws small squares with known texture and polygon colours over a known
## background, reads the screen back and compares each square with what the
## original game's arithmetic gives. It needs a real window, so it is not
## part of the test run:
##
##   godot --path . -s res://tools/probe_model_shader.gd -- --out=<file>
##
## The report goes to the file and to the log. Expected colour behavior is
## documented in docs/reference/rendering/README.md.

## The colour behind the squares.
const BACKGROUND := Color8(100, 60, 20)
## How far a channel may be from the expected value.
const TOLERANCE: int = 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RenderingServer.set_default_clear_color(BACKGROUND)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.position = Vector3(0, 0, 5)
	root.add_child(camera)
	var cases: Array[Array] = [
		["textured, polygon colour 128", Color8(200, 120, 40), Color8(128, 128, 128), ModelShaders.Blend.OPAQUE, Color8(200, 120, 40)],
		["textured, polygon colour 64", Color8(200, 120, 40), Color8(64, 64, 64), ModelShaders.Blend.OPAQUE, Color8(100, 60, 20)],
		["textured, polygon colour 192", Color8(200, 120, 40), Color8(192, 192, 192), ModelShaders.Blend.OPAQUE, Color8(200, 120, 40)],
		["textured, polygon colour 32,64,128", Color8(200, 200, 200), Color8(32, 64, 128), ModelShaders.Blend.OPAQUE, Color8(50, 100, 200)],
		["untextured, polygon colour 90,160,30", null, Color8(90, 160, 30), ModelShaders.Blend.OPAQUE, Color8(90, 160, 30)],
		["untextured, dark polygon colour 4,8,16", null, Color8(4, 8, 16), ModelShaders.Blend.OPAQUE, Color8(4, 8, 16)],
		["textured, dark texture 6,12,24", Color8(6, 12, 24), Color8(128, 128, 128), ModelShaders.Blend.OPAQUE, Color8(6, 12, 24)],
		["transparent texture pixel", Color8(0, 0, 0, 0), Color8(128, 128, 128), ModelShaders.Blend.OPAQUE, BACKGROUND],
		["translucent, average", Color8(200, 120, 40), Color8(128, 128, 128), ModelShaders.Blend.AVERAGE, Color8(150, 90, 30)],
		["translucent, add", Color8(50, 40, 30), Color8(128, 128, 128), ModelShaders.Blend.ADD, Color8(150, 100, 50)],
		["translucent, subtract", Color8(50, 40, 30), Color8(128, 128, 128), ModelShaders.Blend.SUBTRACT, Color8(50, 20, 0)],
		["translucent, add a quarter", Color8(200, 120, 40), Color8(128, 128, 128), ModelShaders.Blend.ADD_QUARTER, Color8(150, 90, 30)],
		["custom ambient 64,64,192", null, Color8(90, 160, 30), ModelShaders.Blend.OPAQUE, Color8(22, 40, 22), Vector3(1024, 1024, 3072)],
		["dive scaled custom ambient", null, Color8(90, 160, 30), ModelShaders.Blend.OPAQUE, Color8(0, 20, 44), Vector3(0, 512, 6112)],
	]
	var centres: Array[Vector3] = []
	for i: int in cases.size():
		var centre := Vector3(-4.0 + 1.6 * (i % 5) + 0.8, 2.0 - 2.0 * (i / 5), 0)
		centres.append(centre)
		var texture_colour: Variant = cases[i][1]
		var polygon_colour: Color = cases[i][2]
		var blend: ModelShaders.Blend = cases[i][3]
		var square: MeshInstance3D = _square(centre, texture_colour, polygon_colour, blend)
		if cases[i].size() > 5:
			var material: ShaderMaterial = square.mesh.surface_get_material(0) as ShaderMaterial
			material.set_shader_parameter("source_lighting", true)
			material.set_shader_parameter("source_ambient", cases[i][5])
		root.add_child(square)
	for _frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var screen: Image = root.get_texture().get_image()
	var lines := PackedStringArray()
	lines.append("renderer: %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	lines.append("video adapter: %s" % RenderingServer.get_video_adapter_name())
	lines.append("background: %s" % _bytes(BACKGROUND))
	var failures: int = 0
	for i: int in cases.size():
		var at: Vector2 = camera.unproject_position(centres[i])
		var got: Color = screen.get_pixelv(Vector2i(at))
		var want: Color = cases[i][4]
		var ok: bool = absi(got.r8 - want.r8) <= TOLERANCE and absi(got.g8 - want.g8) <= TOLERANCE \
			and absi(got.b8 - want.b8) <= TOLERANCE
		if not ok:
			failures += 1
		var case_name: String = cases[i][0]
		lines.append("%s  %s: expected %s, measured %s" % ["ok  " if ok else "FAIL", case_name, _bytes(want), _bytes(got)])
	lines.append("%d of %d as expected (within %d)" % [cases.size() - failures, cases.size(), TOLERANCE])
	var report: String = "\n".join(lines)
	print(report)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file := FileAccess.open(arg.substr(6), FileAccess.WRITE)
			file.store_string(report + "\n")
			file.close()
	quit(1 if failures > 0 else 0)


func _bytes(colour: Color) -> String:
	return "(%d, %d, %d)" % [colour.r8, colour.g8, colour.b8]


func _square(centre: Vector3, texture_colour: Variant, polygon_colour: Color, blend: ModelShaders.Blend) -> MeshInstance3D:
	var texture: ImageTexture = null
	if texture_colour != null:
		var fill: Color = texture_colour
		var image: Image = Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(fill)
		texture = ImageTexture.create_from_image(image)
	var corners := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	for corner: Vector2 in [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		corners.append(centre + Vector3(corner.x, corner.y, 0) * 0.6)
		colours.append(polygon_colour)
		uvs.append(Vector2(0.5, 0.5))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = corners
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, ModelShaders.material(texture, blend, false, false))
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node
