class_name SetupPlayView
extends SetupPageView
## The last page: a summary, whether the setup opens on every start, the
## desktop shortcut, and how to open the setup again.

var _summary: Label
var _show: CheckBox
var _shortcut_result: Label


func build() -> void:
	_summary = add_text(self)
	_show = CheckBox.new()
	_show.text = "Show this setup every time the game starts"
	_show.toggled.connect(func(on: bool) -> void:
		flow.play.show_setup_on_start = on
		edited.emit())
	add_child(_show)
	add_text(self, "To open the setup again later, hold Shift while the game starts, or start it with --setup.", true)
	add_child(HSeparator.new())
	var platform: DesktopShortcut.Platform = DesktopShortcut.platform_of(OS.get_name())
	add_text(self, DesktopShortcut.hint(platform, ImportProcess.from_source()), true)
	if DesktopShortcut.can_create(platform):
		var button := Button.new()
		button.text = "Create a desktop shortcut"
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.pressed.connect(create_shortcut)
		add_child(button)
	_shortcut_result = add_text(self, "", true)


func refresh() -> void:
	var lines := PackedStringArray()
	var root: String = flow.play_root()
	lines.append("The game plays from %s." % root if not root.is_empty() else "Nothing has been imported yet.")
	if flow.game_files.has_game_files():
		lines.append("Game files: %s." % flow.game_files.detection.summary)
	lines.append("Music: %s." % ("from " + flow.game_files.disc_path if not flow.game_files.disc_path.is_empty() else "none"))
	lines.append("FrogLord: %s." % (flow.froglord.folder if flow.froglord.enabled else "off"))
	_summary.text = "\n".join(lines)
	_show.set_pressed_no_signal(flow.play.show_setup_on_start)


## Writes the desktop shortcut and says where.
func create_shortcut() -> void:
	var problems := PackedStringArray()
	var written: PackedStringArray = DesktopShortcut.create(problems)
	var lines := PackedStringArray()
	for path: String in written:
		lines.append("Shortcut written: " + path)
	lines.append_array(problems)
	_shortcut_result.text = "\n".join(lines)
