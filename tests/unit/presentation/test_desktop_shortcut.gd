extends GutTest
## DesktopShortcut's builders: the command that starts the game, the Windows
## PowerShell script and its encoding, and the Linux desktop entry with its
## quoting and paths. Only the running platform can write a shortcut, so the
## content is what is checked here.


func test_platforms_are_named_by_the_os() -> void:
	assert_eq(DesktopShortcut.platform_of("Windows"), DesktopShortcut.Platform.WINDOWS)
	assert_eq(DesktopShortcut.platform_of("Linux"), DesktopShortcut.Platform.LINUX)
	assert_eq(DesktopShortcut.platform_of("FreeBSD"), DesktopShortcut.Platform.LINUX)
	assert_eq(DesktopShortcut.platform_of("macOS"), DesktopShortcut.Platform.MACOS)
	assert_eq(DesktopShortcut.platform_of("Android"), DesktopShortcut.Platform.OTHER)
	assert_true(DesktopShortcut.can_create(DesktopShortcut.Platform.WINDOWS))
	assert_true(DesktopShortcut.can_create(DesktopShortcut.Platform.LINUX))
	assert_false(DesktopShortcut.can_create(DesktopShortcut.Platform.MACOS), "macOS gets a hint, not a button")
	assert_string_contains(DesktopShortcut.hint(DesktopShortcut.Platform.MACOS, false), "Applications or the Dock")


func test_the_launch_command_names_the_project_only_from_source() -> void:
	assert_eq(DesktopShortcut.launch_command("C:/Games/Frogger.exe", false, "C:/src"), PackedStringArray(["C:/Games/Frogger.exe"]))
	assert_eq(DesktopShortcut.launch_command("/usr/bin/godot", true, "/home/me/frogger"),
		PackedStringArray(["/usr/bin/godot", "--path", "/home/me/frogger"]))


func test_windows_arguments_are_quoted_for_the_command_line() -> void:
	assert_eq(DesktopShortcut.windows_quote("--path"), "--path")
	assert_eq(DesktopShortcut.windows_quote("C:\\My Games\\frogger"), "\"C:\\My Games\\frogger\"")
	assert_eq(DesktopShortcut.windows_quote("C:\\My Games\\"), "\"C:\\My Games\\\\\"", "a trailing backslash is doubled")
	assert_eq(DesktopShortcut.windows_quote("say \"hi\""), "\"say \\\"hi\\\"\"")
	assert_eq(DesktopShortcut.windows_quote(""), "\"\"")
	assert_eq(DesktopShortcut.powershell_literal("it's"), "'it''s'")


func test_the_windows_script_writes_the_shortcut() -> void:
	var command := PackedStringArray(["C:\\Godot\\Godot.exe", "--path", "C:\\Users\\Me\\My Frogger"])
	var script: String = DesktopShortcut.windows_script("C:\\Users\\Me\\Desktop\\Frogger.lnk", command,
		"C:\\Users\\Me\\My Frogger", "")
	assert_string_contains(script, "New-Object -ComObject WScript.Shell")
	assert_string_contains(script, ".CreateShortcut('C:\\Users\\Me\\Desktop\\Frogger.lnk')")
	assert_string_contains(script, "$shortcut.TargetPath = 'C:\\Godot\\Godot.exe'")
	assert_string_contains(script, "$shortcut.Arguments = '--path \"C:\\Users\\Me\\My Frogger\"'")
	assert_string_contains(script, "$shortcut.WorkingDirectory = 'C:\\Users\\Me\\My Frogger'")
	assert_string_contains(script, "$shortcut.IconLocation = 'C:\\Godot\\Godot.exe,0'")
	assert_true(script.ends_with("$shortcut.Save()\r\n"))
	var exported: String = DesktopShortcut.windows_script("D:\\Desktop\\Frogger.lnk",
		PackedStringArray(["D:\\Frogger\\Frogger.exe"]), "D:\\Frogger", "D:\\Frogger\\icon.ico")
	assert_string_contains(exported, "$shortcut.Arguments = ''")
	assert_string_contains(exported, "$shortcut.IconLocation = 'D:\\Frogger\\icon.ico,0'")


func test_the_script_reaches_powershell_encoded() -> void:
	var script: String = "Write-Output 'Frogger''s'\r\n"
	var arguments: PackedStringArray = DesktopShortcut.powershell_arguments(script)
	assert_eq(arguments.slice(0, 5), PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand"]))
	var decoded: PackedByteArray = Marshalls.base64_to_raw(arguments[5])
	assert_eq(decoded.size(), script.length() * 2, "UTF-16, two bytes a character")
	assert_eq(decoded[0], "W".unicode_at(0))
	assert_eq(decoded[1], 0, "little-endian")
	assert_eq(decoded.get_string_from_utf16(), script)


func test_desktop_entry_arguments_are_quoted_per_the_specification() -> void:
	assert_eq(DesktopShortcut.desktop_exec_quote("/usr/bin/godot"), "/usr/bin/godot")
	assert_eq(DesktopShortcut.desktop_exec_quote("/home/me/My Frogger"), "\"/home/me/My Frogger\"")
	assert_eq(DesktopShortcut.desktop_exec_quote("/home/me/$x"), "\"/home/me/\\$x\"")
	assert_eq(DesktopShortcut.desktop_exec_quote("100%"), "100%%")
	assert_eq(DesktopShortcut.desktop_exec_quote(""), "\"\"")


func test_the_desktop_entry_starts_the_game() -> void:
	var entry: String = DesktopShortcut.desktop_entry(PackedStringArray(["/opt/godot/godot", "--path", "/home/me/My Frogger"]),
		"/home/me/My Frogger", "")
	var lines: PackedStringArray = entry.split("\n", false)
	assert_eq(lines[0], "[Desktop Entry]")
	assert_true(lines.has("Type=Application"))
	assert_true(lines.has("Name=Frogger"))
	assert_true(lines.has("Exec=/opt/godot/godot --path \"/home/me/My Frogger\""))
	assert_true(lines.has("Path=/home/me/My Frogger"))
	assert_true(lines.has("Terminal=false"))
	assert_false(entry.contains("Icon="), "no icon until the game has one")
	var escaped: String = DesktopShortcut.desktop_entry(PackedStringArray(["/opt/a\\b/game"]), "/opt", "/opt/icon.png")
	assert_string_contains(escaped, "Exec=\"/opt/a\\\\\\\\b/game\"", "a backslash is escaped for the quotes and for the string")
	assert_string_contains(escaped, "Icon=/opt/icon.png")


func test_linux_shortcuts_go_to_the_applications_menu_and_the_desktop() -> void:
	assert_eq(DesktopShortcut.linux_paths("/home/me", "", "/home/me/Desktop"),
		PackedStringArray(["/home/me/.local/share/applications/frogger.desktop", "/home/me/Desktop/frogger.desktop"]))
	assert_eq(DesktopShortcut.linux_paths("/home/me", "/data", ""),
		PackedStringArray(["/data/applications/frogger.desktop"]))


func test_the_linux_icon_sits_beside_an_export_or_in_the_project() -> void:
	assert_eq(DesktopShortcut.linux_icon("/opt/Frogger/Frogger.x86_64", false, "/ignored"), "/opt/Frogger/frogger.png")
	assert_eq(DesktopShortcut.linux_icon("/usr/bin/godot", true, "/home/me/frogger-godot"),
		"/home/me/frogger-godot/icon/frogger_icon.png")
