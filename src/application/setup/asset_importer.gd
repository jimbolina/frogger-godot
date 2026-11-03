class_name AssetImporter
extends RefCounted
## Imports the player's own copy of the game into an asset root the game can
## open, without Godot's editor import.
##
## This is the interface the setup screen is typed against;
## [code]AssetImporterFactory.create()[/code] returns the implementation.
## Neither method touches a node or the scene tree. [param progress] and
## [param cancelled] are called on the thread that runs [method run], so when
## that is a worker thread they must be safe to call from it (for example, by
## deferring UI work). The implementation saves meshes and materials, which
## query the RenderingServer; a worker-thread run has been seen to stall there
## headless, so check it with a window before relying on it.

## The folder imported roots live in, one sub-folder per fingerprint.
const ROOT_PARENT: String = "user://assets"
## The only build the importer accepts.
const SUPPORTED_BUILD: String = "pc-retail-v3.0e"


## What [method detect] found in a game folder.
class Detection:
	extends RefCounted
	## Why the folder cannot be imported (no game files, an unknown or
	## unsupported build), or "" when it can.
	var error: String = ""
	## The detected build's internal name, for example
	## [code]pc-retail-v3.0e[/code]; "" when none was detected.
	var build: String = ""
	## The detected build's name for people; "" when none was detected.
	var build_name: String = ""
	## The first 16 hex digits of the SHA-256 over the game files read, which
	## name the imported root; "" when there are no game files.
	var fingerprint: String = ""
	## One line for people: the build, the kind of files and where they are.
	var summary: String = ""

	## True when the folder holds a build the importer accepts.
	func is_ok() -> bool:
		return error.is_empty() and not fingerprint.is_empty()


## Remarks from the last [method run] that did not fail it, such as an import
## without a disc image and so without music.
var notes: PackedStringArray = PackedStringArray()


## The imported root for [param fingerprint]: [code]user://assets/<fingerprint>[/code].
static func root_for(fingerprint: String) -> String:
	return ROOT_PARENT.path_join(fingerprint)


## Reports which build the game files in [param data_dir] are and whether
## they can be imported.
@warning_ignore("unused_parameter")
func detect(data_dir: String) -> Detection:
	var detection := Detection.new()
	detection.error = "no importer is available"
	return detection


## Imports the game files in [param data_dir], and the music from the disc
## image [param disc_path] when it is not empty, into [param target_root].
## Calls [code]progress.call(fraction: float, label: String)[/code] as the
## import advances (fraction from 0 to 1) and stops soon after
## [code]cancelled.call()[/code] returns true; pass an empty [Callable] for
## either when nobody follows or cancels the run.
## The root appears complete or not at all: it is written under another name
## and renamed on success, replacing an earlier root there. Returns the
## problems, empty on success; [member notes] holds the remarks.
@warning_ignore("unused_parameter")
func run(data_dir: String, disc_path: String, target_root: String,
		progress: Callable, cancelled: Callable) -> PackedStringArray:
	notes = PackedStringArray()
	return PackedStringArray(["no importer is available"])
