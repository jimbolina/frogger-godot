extends SceneTree
## Writes the app icon files from icon/frogger_icon.svg, or with --check after
## -- compares them with the committed files and exits 1 on a difference.
## Run with godot --headless --path . -s res://tools/make_icons.gd [-- --check].

const AppIcons = preload("res://tools/support/app_icons.gd")


func _init() -> void:
	var check: bool = OS.get_cmdline_user_args().has("--check")
	var outputs: Dictionary[String, PackedByteArray] = AppIcons.outputs()
	var failed: int = 0
	for path: String in outputs:
		var data: PackedByteArray = outputs[path]
		if data.is_empty():
			print("make_icons: %s could not be rendered" % path)
			failed += 1
			continue
		if check:
			if FileAccess.get_file_as_bytes(path) != data:
				print("make_icons: %s differs from its source" % path)
				failed += 1
			continue
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			print("make_icons: %s could not be written" % path)
			failed += 1
			continue
		file.store_buffer(data)
		file.close()
		print("make_icons: wrote %s (%d bytes)" % [path, data.size()])
	quit(1 if failed > 0 else 0)
