class_name DesktopShortcut
extends RefCounted
## A desktop shortcut that starts the game: a [code].lnk[/code] on the Windows
## desktop, made through PowerShell's [code]WScript.Shell[/code], or a
## [code].desktop[/code] entry in the Linux applications folder and on the
## desktop, marked executable. macOS has no button: the player drags the app
## to Applications or the Dock.
##
## The static builders return file contents and command lines from their
## arguments alone, so every platform's output can be checked anywhere;
## [method create] gathers the real paths and writes for the running platform.
## From source the shortcut starts the engine with [code]--path[/code] and the
## project folder; an exported game starts its own executable.

## The platforms the screen knows.
enum Platform { OTHER, WINDOWS, LINUX, MACOS }

## The shortcut's name.
const NAME: String = "Frogger"
## The shortcut's description.
const COMMENT: String = "Frogger (1997) in Godot"
## The Windows shortcut file.
const WINDOWS_FILE: String = "Frogger.lnk"
## The Linux desktop entry file.
const LINUX_FILE: String = "frogger.desktop"
## The icon a Linux export ships beside its executable.
const LINUX_ICON: String = "frogger.png"
## The project's icon, which a source run's desktop entry shows.
const PROJECT_ICON: String = "icon/frogger_icon.png"
## The PowerShell executable.
const POWERSHELL: String = "powershell.exe"
## The permissions of a written desktop entry: rwxr-xr-x.
const EXECUTABLE_MODE: int = FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER \
	| FileAccess.UNIX_READ_GROUP | FileAccess.UNIX_EXECUTE_GROUP | FileAccess.UNIX_READ_OTHER | FileAccess.UNIX_EXECUTE_OTHER
const _DESKTOP_RESERVED: String = " \t\n\"'\\><~|&;$*?#()`"


## The platform called [param os_name] by [method OS.get_name].
static func platform_of(os_name: String) -> Platform:
	match os_name:
		"Windows", "UWP":
			return Platform.WINDOWS
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return Platform.LINUX
		"macOS":
			return Platform.MACOS
	return Platform.OTHER


## Whether a shortcut button is offered on [param platform].
static func can_create(platform: Platform) -> bool:
	return platform == Platform.WINDOWS or platform == Platform.LINUX


## What the setup screen says about shortcuts on [param platform].
static func hint(platform: Platform, source_run: bool) -> String:
	match platform:
		Platform.WINDOWS:
			return "Put a shortcut to the game on your desktop."
		Platform.LINUX:
			return "Add the game to your applications menu and your desktop."
		Platform.MACOS:
			if source_run:
				return "On macOS, start a source checkout with tools/launch_macos.command; an exported Frogger app can be dragged to Applications or the Dock."
			return "On macOS, drag the Frogger app to Applications or the Dock to start it from there."
	return "Shortcuts are not made on this system."


## The program and arguments that start the game: [param executable] alone for
## an exported game, or with [code]--path[/code] and [param project_dir] from source.
static func launch_command(executable: String, source_run: bool, project_dir: String) -> PackedStringArray:
	var command := PackedStringArray([executable])
	if source_run:
		command.append_array(["--path", project_dir])
	return command


## [param argument] quoted for a Windows command line, as
## [code]CommandLineToArgvW[/code] reads it.
static func windows_quote(argument: String) -> String:
	if not argument.is_empty() and not argument.contains(" ") and not argument.contains("\t") \
			and not argument.contains("\""):
		return argument
	var quoted: String = "\""
	var backslashes: int = 0
	for character: String in argument:
		if character == "\\":
			backslashes += 1
			continue
		if character == "\"":
			quoted += "\\".repeat(backslashes * 2 + 1) + "\""
		else:
			quoted += "\\".repeat(backslashes) + character
		backslashes = 0
	return quoted + "\\".repeat(backslashes * 2) + "\""


## [param text] as a single-quoted PowerShell string.
static func powershell_literal(text: String) -> String:
	return "'" + text.replace("'", "''") + "'"


## The PowerShell script that writes the shortcut [param link_path] starting
## [param command] (program first) in [param working_dir], with the icon of
## [param icon_path] ("" for the program's own).
static func windows_script(link_path: String, command: PackedStringArray, working_dir: String,
		icon_path: String) -> String:
	var arguments := PackedStringArray()
	for index: int in range(1, command.size()):
		arguments.append(windows_quote(command[index]))
	var icon: String = icon_path if not icon_path.is_empty() else command[0]
	var lines := PackedStringArray([
		"$ErrorActionPreference = 'Stop'",
		"$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut(%s)" % powershell_literal(link_path),
		"$shortcut.TargetPath = %s" % powershell_literal(command[0]),
		"$shortcut.Arguments = %s" % powershell_literal(" ".join(arguments)),
		"$shortcut.WorkingDirectory = %s" % powershell_literal(working_dir),
		"$shortcut.IconLocation = %s" % powershell_literal(icon + ",0"),
		"$shortcut.Description = %s" % powershell_literal(COMMENT),
		"$shortcut.Save()",
	])
	return "\r\n".join(lines) + "\r\n"


## The PowerShell arguments that run [param script]; the script travels
## base64-encoded as UTF-16LE, so no quoting of it can go wrong.
static func powershell_arguments(script: String) -> PackedStringArray:
	return PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-EncodedCommand", Marshalls.raw_to_base64(script.to_utf16_buffer())])


## [param argument] quoted for the [code]Exec[/code] key of a desktop entry.
static func desktop_exec_quote(argument: String) -> String:
	var needs_quotes: bool = argument.is_empty()
	for character: String in argument:
		needs_quotes = needs_quotes or _DESKTOP_RESERVED.contains(character)
	var escaped: String = argument.replace("%", "%%")
	if not needs_quotes:
		return escaped
	for character: String in ["\\", "\"", "`", "$"]:
		escaped = escaped.replace(character, "\\" + character)
	return "\"" + escaped + "\""


## The icon file a Linux desktop entry shows: [constant LINUX_ICON] beside
## [param executable] for an exported game, [constant PROJECT_ICON] under
## [param project_dir] from source.
static func linux_icon(executable: String, source_run: bool, project_dir: String) -> String:
	return project_dir.path_join(PROJECT_ICON) if source_run else executable.get_base_dir().path_join(LINUX_ICON)


## The desktop entry starting [param command] (program first) in
## [param working_dir], with [param icon_path] when it is not empty.
static func desktop_entry(command: PackedStringArray, working_dir: String, icon_path: String) -> String:
	var exec := PackedStringArray()
	for part: String in command:
		exec.append(desktop_exec_quote(part))
	var lines := PackedStringArray([
		"[Desktop Entry]",
		"Type=Application",
		"Version=1.0",
		"Name=" + NAME,
		"Comment=" + COMMENT,
		"Exec=" + _desktop_string(" ".join(exec)),
		"Path=" + _desktop_string(working_dir),
		"Terminal=false",
		"Categories=Game;ArcadeGame;",
	])
	if not icon_path.is_empty():
		lines.append("Icon=" + _desktop_string(icon_path))
	return "\n".join(lines) + "\n"


## The Linux files a shortcut is written to: the applications folder under
## [param data_home] (or [code]~/.local/share[/code] under [param home] when
## empty) and [param desktop_dir] when it is not empty.
static func linux_paths(home: String, data_home: String, desktop_dir: String) -> PackedStringArray:
	var share: String = data_home if not data_home.is_empty() else home.path_join(".local/share")
	var paths := PackedStringArray([share.path_join("applications").path_join(LINUX_FILE)])
	if not desktop_dir.is_empty():
		paths.append(desktop_dir.path_join(LINUX_FILE))
	return paths


## Makes the shortcut for the running game and returns the files written;
## each failure is appended to [param problems].
static func create(problems: PackedStringArray) -> PackedStringArray:
	var source_run: bool = not OS.has_feature("template")
	var executable: String = OS.get_executable_path()
	var project_dir: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var command: PackedStringArray = launch_command(executable, source_run, project_dir)
	var working_dir: String = project_dir if source_run else executable.get_base_dir()
	var desktop: String = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	var written := PackedStringArray()
	match platform_of(OS.get_name()):
		Platform.WINDOWS:
			var link: String = desktop.path_join(WINDOWS_FILE).replace("/", "\\")
			var output: Array = []
			var code: int = OS.execute(POWERSHELL,
				powershell_arguments(windows_script(link, command, working_dir.replace("/", "\\"), "")), output, true)
			if code != 0:
				problems.append("PowerShell could not write %s (exit code %d): %s" % [link, code, "".join(output).strip_edges()])
			else:
				written.append(link)
		Platform.LINUX:
			var icon: String = linux_icon(executable, source_run, project_dir)
			var entry: String = desktop_entry(command, working_dir, icon if FileAccess.file_exists(icon) else "")
			for path: String in linux_paths(OS.get_environment("HOME"), OS.get_environment("XDG_DATA_HOME"), desktop):
				var problem: String = _write_executable(path, entry)
				if problem.is_empty():
					written.append(path)
				else:
					problems.append(problem)
		_:
			problems.append(hint(platform_of(OS.get_name()), source_run))
	return written


static func _write_executable(path: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "%s could not be written (%s)" % [path, error_string(FileAccess.get_open_error())]
	file.store_string(text)
	file.close()
	var made: Error = FileAccess.set_unix_permissions(path, EXECUTABLE_MODE)
	if made != OK:
		return "%s could not be marked executable (%s)" % [path, error_string(made)]
	return ""


static func _desktop_string(value: String) -> String:
	return value.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")
