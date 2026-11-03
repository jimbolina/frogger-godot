extends GutTest
## ImportCommand builds the setup import process's command line and reads it
## back in the child, refusing an incomplete one.


func _command() -> ImportCommand:
	var command := ImportCommand.new()
	command.data_dir = "/Games/My Frogger"
	command.disc_path = "/Discs/FROGGER.mds"
	command.target_root = "user://assets/0123456789abcdef"
	command.progress_path = "/Users/me/Library/Frogger/setup/import_progress.txt"
	command.user_dir = "/Users/me/Library/Frogger"
	return command


func test_a_source_run_names_the_project_and_an_exported_one_does_not() -> void:
	var source: PackedStringArray = _command().arguments("res://scenes/setup.tscn", true, "/src/frogger", "/logs/import.log")
	assert_eq(source.slice(0, 7), PackedStringArray(["--headless", "--path", "/src/frogger", "--log-file", "/logs/import.log",
		"res://scenes/setup.tscn", "--"]))
	assert_eq(source.slice(7), _command().user_arguments())
	var exported: PackedStringArray = _command().arguments("res://scenes/setup.tscn", false, "/src/frogger", "")
	assert_eq(exported.slice(0, 3), PackedStringArray(["--headless", "res://scenes/setup.tscn", "--"]))
	assert_false(exported.has("--path"))


func test_the_user_arguments_read_back() -> void:
	var arguments: PackedStringArray = _command().user_arguments()
	assert_true(ImportCommand.is_requested(arguments))
	var read: ImportCommand = ImportCommand.parse(arguments)
	assert_eq(read.error, "")
	assert_eq(read.data_dir, "/Games/My Frogger", "a folder with a space stays one argument")
	assert_eq(read.disc_path, "/Discs/FROGGER.mds")
	assert_eq(read.target_root, "user://assets/0123456789abcdef")
	assert_eq(read.progress_path, "/Users/me/Library/Frogger/setup/import_progress.txt")
	assert_eq(read.user_dir, "/Users/me/Library/Frogger")


func test_no_disc_leaves_the_disc_out() -> void:
	var command: ImportCommand = _command()
	command.disc_path = ""
	var arguments: PackedStringArray = command.user_arguments()
	for argument: String in arguments:
		assert_false(argument.begins_with(ImportCommand.DISC_ARGUMENT))
	var read: ImportCommand = ImportCommand.parse(arguments)
	assert_eq(read.error, "")
	assert_eq(read.disc_path, "")


func test_an_incomplete_command_is_refused() -> void:
	var read: ImportCommand = ImportCommand.parse(PackedStringArray(["--data-dir=/Games"]))
	assert_string_contains(read.error, "--setup-import")
	assert_string_contains(read.error, "--target")
	assert_string_contains(read.error, "--progress")
	assert_string_contains(read.error, "--user-dir")
	assert_false(read.error.contains("--data-dir"))
	assert_false(ImportCommand.is_requested(PackedStringArray(["--setup"])))


func test_the_user_folder_must_match() -> void:
	var command: ImportCommand = _command()
	assert_true(command.same_user_dir("/Users/me/Library/Frogger/"))
	assert_true(command.same_user_dir("/Users/me/Library/./Frogger"))
	assert_false(command.same_user_dir("/Users/me/Library/Frogger Automation/abc"))
	command.user_dir = "C:\\Users\\Me\\AppData\\Roaming\\Godot\\app_userdata\\Frogger"
	assert_true(command.same_user_dir("c:/users/me/AppData/Roaming/Godot/app_userdata/Frogger/"))
