class_name FrogLordWatch
extends RefCounted
## When the running game imports FrogLord's save again: the change, stability
## and import states of the in-game watch, without files or threads.
##
## The watcher node calls [method poll] about once a second with whether the
## save folder exists and its [code]AssetImporter.source_state[/code]. A state
## that differs from the one the current overlay was imported from, and that
## has stayed the same for one more poll, starts an import: [method poll]
## returns true and the phase is [constant Phase.IMPORTING] until
## [method finish] gets the result. A result to retry is tried again once the
## files change, or after [constant RETRY_POLLS] polls of the same files; a
## failed import is not repeated until the files change again. [member message] is one line for people and
## [member revision] grows whenever it changes.

## Where the watch stands.
enum Phase {
	## FrogLord is off.
	OFF,
	## FrogLord is on but its folder is not chosen or does not exist.
	NO_FOLDER,
	## The folder holds no FrogLord save and no game files.
	NO_SAVE,
	## The save changed and is waiting for one more unchanged poll.
	SETTLING,
	## An import is running.
	IMPORTING,
	## The files could not be imported yet; the next poll tries again.
	WAITING,
	## The pointer names an overlay of the current files.
	READY,
	## The current files could not be imported.
	FAILED,
}

## Polls of unchanged files after which a result to retry is tried again.
const RETRY_POLLS: int = 5

## The save folder watched.
var folder: String = ""
## The base root the overlays fall back to.
var base_root: String = ""
## Where the watch stands.
var phase: Phase = Phase.OFF
## One line for people about [member phase].
var message: String = ""
## Grows by one whenever [member message] changes.
var revision: int = 0
## True while [member message] reports a problem rather than progress.
var warning: bool = false
## The unmapped support-report rows of the last clean import, tab-separated.
var unmapped: PackedStringArray = PackedStringArray()
## The support report of the last clean import, or "".
var report_path: String = ""

var _previous: String = ""
var _handled: String = ""
var _handled_phase: Phase = Phase.OFF
var _handled_message: String = ""
var _handled_warning: bool = false
var _importing: String = ""
var _retry_state: String = ""
var _retry_polls: int = 0


## A watch of [param save_folder] over [param base] when [param enabled]. When
## [param pointer] names an overlay of that folder over that base, its
## [member FrogLordPointer.source_state] counts as already imported, so
## unchanged files are not imported again at start.
static func create(enabled: bool, save_folder: String, base: String, pointer: FrogLordPointer) -> FrogLordWatch:
	var watch := FrogLordWatch.new()
	watch.folder = save_folder
	watch.base_root = base
	if not enabled:
		watch._say(Phase.OFF, "", false)
		return watch
	if save_folder.is_empty():
		watch._say(Phase.NO_FOLDER, "FrogLord is on but no save folder is chosen; playing the imported files. Choose one in the setup (--setup).", true)
		return watch
	if pointer != null and pointer.exists() and pointer.data_dir == save_folder and pointer.fallback_root == base \
			and not pointer.source_state.is_empty():
		watch._handled = pointer.source_state
		watch._handled_phase = Phase.READY
		watch._handled_message = "FrogLord: playing %s." % (pointer.source_summary if not pointer.source_summary.is_empty() else pointer.index_root)
		watch.report_path = pointer.report_path
	watch._say(Phase.SETTLING, "FrogLord: watching %s." % save_folder, false)
	return watch


## True when the watch follows a folder.
func is_on() -> bool:
	return phase != Phase.OFF and not folder.is_empty()


## Takes one poll: whether the save folder exists and its source state ("" when
## it holds no pair). Returns true when an import should start now; the caller
## then runs it and passes the result to [method finish].
func poll(folder_exists: bool, state: String) -> bool:
	if phase == Phase.OFF or folder.is_empty() or phase == Phase.IMPORTING:
		return false
	if not folder_exists:
		_previous = ""
		_say(Phase.NO_FOLDER, "FrogLord: the save folder %s is missing; playing the imported files until it returns." % folder, true)
		return false
	if state.is_empty():
		_previous = ""
		_say(Phase.NO_SAVE, "FrogLord: %s holds no FrogLord save (modded_FROGGER.EXE and modded_FROGPSX.MWD) yet." % folder, true)
		return false
	if state == _handled:
		_previous = state
		_say(_handled_phase, _handled_message, _handled_warning)
		return false
	if state != _previous:
		_previous = state
		_retry_state = ""
		if _handled.is_empty():
			_say(Phase.SETTLING, "FrogLord: found the save in %s." % folder, false)
		else:
			_say(Phase.SETTLING, "FrogLord: the save in %s changed; waiting for FrogLord to finish writing it." % folder, false)
		return false
	if state == _retry_state:
		_retry_polls += 1
		if _retry_polls < RETRY_POLLS:
			return false
	_retry_state = ""
	_importing = state
	_say(Phase.IMPORTING, "FrogLord: importing the save in %s." % folder, false)
	return true


## Takes the result of the import [method poll] asked for.
func finish(result: AssetImporter.OverlayResult) -> void:
	if phase != Phase.IMPORTING:
		return
	var imported: String = result.source_state if not result.source_state.is_empty() else _importing
	_importing = ""
	if not result.retry.is_empty():
		_retry_state = imported
		_retry_polls = 0
		_say(Phase.WAITING, "FrogLord: waiting (%s)." % result.retry, true)
		return
	if not result.error.is_empty():
		_remember(imported, Phase.FAILED, "FrogLord: cannot import the save (%s); playing the last overlay or the imported files." % result.error, true)
		return
	if not result.problems.is_empty():
		_remember(imported, Phase.FAILED, "FrogLord: the save could not be imported (%s); playing the last overlay or the imported files." % result.problems[0], true)
		return
	unmapped = result.unmapped
	report_path = result.report_path
	var text: String = "FrogLord: imported %s." % (result.source_summary if not result.source_summary.is_empty() else result.index_root)
	if not unmapped.is_empty():
		text += " %d forms, entities or remaps the port cannot play are listed in %s." % [unmapped.size(), result.report_path]
	_remember(imported, Phase.READY, text, not unmapped.is_empty())


## Stops the watch, as when FrogLord is turned off.
func stop() -> void:
	_importing = ""
	_say(Phase.OFF, "", false)


func _remember(state: String, chosen: Phase, text: String, is_warning: bool) -> void:
	_handled = state
	_previous = state
	_handled_phase = chosen
	_handled_message = text
	_handled_warning = is_warning
	_say(chosen, text, is_warning)


func _say(chosen: Phase, text: String, is_warning: bool) -> void:
	phase = chosen
	warning = is_warning
	if text != message:
		message = text
		revision += 1
