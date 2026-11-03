class_name AssetImporter
extends RefCounted
## Imports the player's own copy of the game into an asset root the game can
## open, without Godot's editor import, and a FrogLord save into an overlay
## over such a root.
##
## This is the interface the setup screen and the in-game FrogLord watcher are
## typed against; [code]AssetImporterFactory.create()[/code] returns the
## implementation. No method touches a node or the scene tree.
## [param progress] and [param cancelled] are called on the thread that runs
## [method run] or [method import_overlay], so when that is a worker thread
## they must be safe to call from it (for example, by deferring UI work).
## [method run] saves meshes and materials, which query the RenderingServer,
## and stalls on a worker thread; [method import_overlay] saves no meshes or
## materials and may run on one.

## The folder imported roots live in, one sub-folder per fingerprint.
const ROOT_PARENT: String = "user://assets"
## The only build the importer accepts.
const SUPPORTED_BUILD: String = "pc-retail-v3.0e"
## The folder FrogLord overlays over the committed assets live in, one
## sub-folder per save.
const OVERLAY_PARENT: String = "user://froglord"
## The committed assets root, which overlays fall back to by default.
const COMMITTED_ROOT: String = "res://assets"


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
	## True when the files are FrogLord's [code]modded_[/code] pair rather
	## than the retail pair.
	var froglord: bool = false
	## The FrogLord version a FrogLord save's trailer names, or -1.
	var froglord_version: int = -1
	## The executable and archive file names read, joined by " + ", or "".
	var files: String = ""

	## True when the folder holds a build the importer accepts.
	func is_ok() -> bool:
		return error.is_empty() and not fingerprint.is_empty()


## What [method import_overlay] did.
class OverlayResult:
	extends RefCounted
	## Why the import could not start (no folder, no game files, a bad base
	## root), or "".
	var error: String = ""
	## Why the files could not be imported yet (an unfinished save, a change
	## during the import), or ""; a later attempt may succeed.
	var retry: String = ""
	## The overlay key: the first 16 hex digits of the save's fingerprint.
	var key: String = ""
	## The overlay folder, holding its own [code]catalog.tres[/code].
	var index_root: String = ""
	## The base root the overlay falls back to.
	var fallback_root: String = ""
	## The state [method source_state] gave for the folder when the import began.
	var source_state: String = ""
	## [method ImportedAssets.source_summary] of the overlay.
	var source_summary: String = ""
	## Problems that failed the import; the pointer was not written.
	var problems: PackedStringArray = PackedStringArray()
	## [method LevelSupportReport.summary] of the save.
	var support_summary: String = ""
	## The rows of the save's [LevelSupportReport] that a playable level uses
	## and the port cannot play, tab-separated.
	var unmapped: PackedStringArray = PackedStringArray()
	## Read problems of the support report.
	var support_problems: PackedStringArray = PackedStringArray()
	## The support report file beside the overlay index.
	var report_path: String = ""
	## How long the import took.
	var milliseconds: int = 0

	## True when the overlay was imported cleanly and the pointer written.
	func is_ok() -> bool:
		return error.is_empty() and retry.is_empty() and problems.is_empty()


## Remarks from the last [method run] that did not fail it, such as an import
## without a disc image and so without music.
var notes: PackedStringArray = PackedStringArray()
## The folder [method import_overlay] writes overlay folders into.
var overlay_parent: String = OVERLAY_PARENT
## The pointer file [method import_overlay] rewrites after a clean import.
var pointer_path: String = FrogLordPointer.DEFAULT_PATH


## The imported root for [param fingerprint]: [code]user://assets/<fingerprint>[/code].
static func root_for(fingerprint: String) -> String:
	return ROOT_PARENT.path_join(fingerprint)


## The folder overlays over [param base_root] are written into:
## [constant OVERLAY_PARENT] for the committed assets, so the developer watch
## and the game share them, and otherwise a sub-folder of it named by the base
## root, so overlays of one save over different roots never share a folder.
static func overlay_parent_for(base_root: String) -> String:
	if base_root.is_empty() or base_root == COMMITTED_ROOT:
		return OVERLAY_PARENT
	return OVERLAY_PARENT.path_join("over-" + base_root.sha256_text().substr(0, 16))


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


## Reports what FrogLord's save folder [param froglord_dir] holds: FrogLord's
## [code]modded_[/code] pair (preferred) or the retail pair, and its build.
## [member Detection.fingerprint] is empty when the folder holds neither.
@warning_ignore("unused_parameter")
func detect_froglord(froglord_dir: String) -> Detection:
	var detection := Detection.new()
	detection.error = "no importer is available"
	return detection


## A cheap description of the save files in [param froglord_dir] (each file's
## name, modification time and size) that changes whenever FrogLord writes
## them; "" when the folder holds no pair.
@warning_ignore("unused_parameter")
func source_state(froglord_dir: String) -> String:
	return ""


## Imports the save in [param froglord_dir] as an overlay: its name lists,
## tables, demos and maps under [code]<overlay_parent>/<key>/[/code], with an
## index that names [param base_root] for everything else, and its
## [LevelSupportReport] beside it. A clean import rewrites the pointer at
## [member pointer_path]. [param progress] and [param cancelled] are as for
## [method run].
@warning_ignore("unused_parameter")
func import_overlay(froglord_dir: String, base_root: String,
		progress: Callable, cancelled: Callable) -> OverlayResult:
	var result := OverlayResult.new()
	result.error = "no importer is available"
	return result
