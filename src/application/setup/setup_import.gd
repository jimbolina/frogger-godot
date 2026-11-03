class_name SetupImport
extends SetupPage
## The import page: whether the chosen game files still need importing, the
## progress of a running import and how it ended.
##
## [method prepare] decides from the chosen and the recorded fingerprints: a
## root already imported from the same files is kept (and may be imported
## again), other files need an import, and no files need none. The view runs
## the import and reports its progress and end here.

## Where the page stands.
enum State { NOT_NEEDED, READY, EXISTING, RUNNING, SUCCEEDED, FAILED, CANCELLED }

## Where the page stands.
var state: State = State.NOT_NEEDED
## The root the import writes, [code]user://assets/<fingerprint>[/code], or "".
var target_root: String = ""
## The fingerprint of the files being imported, or "".
var fingerprint: String = ""
## The progress of the running or last import, 0 to 1.
var fraction: float = 0.0
## What the import is doing.
var label: String = ""
## Why the last import failed, one line each.
var problems := PackedStringArray()
## Remarks of the last import that did not fail it, such as having no music.
var notes := PackedStringArray()


func title() -> String:
	return "Import"


func blocker() -> String:
	match state:
		State.READY:
			return "Import the game files first."
		State.RUNNING:
			return "The import is still running."
		State.FAILED:
			return "The import failed; retry it or choose other game files."
		State.CANCELLED:
			return "The import was cancelled; retry it or choose other game files."
	return ""


func can_go_back() -> bool:
	return state != State.RUNNING


## Decides what the page offers for files of [param chosen_fingerprint] ("" for
## none chosen), given the [param recorded_fingerprint] and
## [param recorded_root] of the launcher settings and whether the root for the
## chosen files already holds an index ([param target_has_index]). Keeps a
## running import as it is.
func prepare(chosen_fingerprint: String, recorded_fingerprint: String, recorded_root: String,
		target_has_index: bool) -> void:
	if state == State.RUNNING:
		return
	problems = PackedStringArray()
	notes = PackedStringArray()
	fraction = 0.0
	label = ""
	fingerprint = chosen_fingerprint
	if chosen_fingerprint.is_empty():
		target_root = ""
		state = State.NOT_NEEDED
		return
	target_root = AssetImporter.root_for(chosen_fingerprint)
	if chosen_fingerprint == recorded_fingerprint and recorded_root == target_root and target_has_index:
		state = State.EXISTING
		fraction = 1.0
		return
	state = State.READY


## Whether the view should start the import as soon as the page opens.
func starts_on_entry() -> bool:
	return state == State.READY


## Whether an import (first, again or a retry) may start now.
func can_start() -> bool:
	return not target_root.is_empty() and state != State.RUNNING


## Marks the import as running; false when it may not start.
func start() -> bool:
	if not can_start():
		return false
	state = State.RUNNING
	fraction = 0.0
	label = "Starting"
	problems = PackedStringArray()
	notes = PackedStringArray()
	return true


## Records the running import's progress; the fraction never goes back.
func advance(progress_fraction: float, progress_label: String) -> void:
	if state != State.RUNNING:
		return
	fraction = maxf(fraction, clampf(progress_fraction, 0.0, 1.0))
	if not progress_label.is_empty():
		label = progress_label


## Ends the running import: it succeeded when [param failures] is empty.
func finish(failures: PackedStringArray, remarks: PackedStringArray) -> void:
	if state != State.RUNNING:
		return
	problems = failures.duplicate()
	notes = remarks.duplicate()
	if problems.is_empty():
		state = State.SUCCEEDED
		fraction = 1.0
		label = "Done"
	else:
		state = State.FAILED


## Ends the running import as cancelled; false when none was running.
func cancel() -> bool:
	if state != State.RUNNING:
		return false
	state = State.CANCELLED
	label = "Cancelled"
	return true


## True when the game can play from [member target_root].
func has_root() -> bool:
	return state == State.SUCCEEDED or state == State.EXISTING
