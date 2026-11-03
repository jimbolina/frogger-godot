class_name SetupImportView
extends SetupPageView
## The import page: runs the import in a child process ([ImportProcess]),
## shows its progress, and offers cancel, retry and import again.
##
## The import starts by itself when the page appears for files not imported
## yet. A finished import is recorded in the launcher settings at once.

## Seconds between two reads of the progress file.
const POLL_INTERVAL: float = 0.1

var _status: Label
var _bar: ProgressBar
var _step: Label
var _start: Button
var _cancel: Button
var _details: Label
var _since_poll: float = 0.0


func build() -> void:
	_status = add_text(self)
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.custom_minimum_size.y = 24
	add_child(_bar)
	_step = add_text(self, "", true)
	var row := HBoxContainer.new()
	add_child(row)
	_start = Button.new()
	_start.pressed.connect(start_import)
	row.add_child(_start)
	_cancel = Button.new()
	_cancel.text = "Cancel"
	_cancel.pressed.connect(cancel_import)
	row.add_child(_cancel)
	_details = add_text(self, "", true)
	set_process(false)


func refresh() -> void:
	var page: SetupImport = flow.import_page
	_bar.value = page.fraction
	_step.text = page.label
	_bar.visible = page.state != SetupImport.State.NOT_NEEDED
	_start.visible = page.can_start()
	_cancel.visible = page.state == SetupImport.State.RUNNING
	match page.state:
		SetupImport.State.NOT_NEEDED:
			_status.text = "No game files were chosen, so nothing is imported; the game plays from %s." % flow.base_root
		SetupImport.State.READY:
			_status.text = "Ready to import into %s." % page.target_root
			_start.text = "Import"
		SetupImport.State.EXISTING:
			_status.text = "These game files were imported already, into %s." % page.target_root
			_start.text = "Import again"
		SetupImport.State.RUNNING:
			_status.text = "Importing into %s. This takes about twenty seconds." % page.target_root
		SetupImport.State.SUCCEEDED:
			_status.text = "Imported into %s." % page.target_root
			_start.text = "Import again"
		SetupImport.State.FAILED:
			_status.text = "The import failed."
			_start.text = "Retry"
		SetupImport.State.CANCELLED:
			_status.text = "The import was cancelled."
			_start.text = "Retry"
	var lines := PackedStringArray()
	for problem: String in page.problems:
		lines.append("Problem: " + problem)
	for note: String in page.notes:
		lines.append("Note: " + note)
	if page.state == SetupImport.State.FAILED or page.state == SetupImport.State.CANCELLED:
		lines.append("The import log is %s." % ProjectSettings.globalize_path(screen.import_process.log_path))
	_details.text = "\n".join(lines)


func shown() -> void:
	flow.prepare_import(ImportedAssets.has_index(flow.import_target()))
	refresh()
	if flow.import_page.starts_on_entry():
		start_import()


## Starts the import (the first time, again or as a retry).
func start_import() -> void:
	if not flow.import_page.start():
		return
	var command := ImportCommand.new()
	command.data_dir = flow.game_files.data_dir
	command.disc_path = flow.game_files.disc_path
	command.target_root = flow.import_page.target_root
	if not screen.import_process.start(command):
		flow.import_page.finish(PackedStringArray([screen.import_process.error]), PackedStringArray())
		refresh()
		edited.emit()
		return
	_since_poll = 0.0
	set_process(true)
	refresh()
	edited.emit()


## Stops the running import and removes what it wrote.
func cancel_import() -> void:
	if not flow.import_page.cancel():
		return
	screen.import_process.cancel()
	set_process(false)
	refresh()
	edited.emit()


## Reads the child's progress once; called every [constant POLL_INTERVAL] while it runs.
func poll() -> void:
	if flow.import_page.state != SetupImport.State.RUNNING:
		set_process(false)
		return
	var report: ImportProgress = screen.import_process.poll()
	flow.import_page.advance(report.fraction, report.label)
	if report.finished:
		set_process(false)
		var problems: PackedStringArray = report.problems.duplicate()
		if not report.succeeded and problems.is_empty():
			problems.append("the import reported a failure without a reason")
		flow.import_page.finish(problems, report.notes)
		if flow.record_import():
			screen.save_launcher()
	refresh()
	edited.emit()


func _process(delta: float) -> void:
	_since_poll += delta
	if _since_poll < POLL_INTERVAL:
		return
	_since_poll = 0.0
	poll()


func _exit_tree() -> void:
	if flow != null and flow.import_page.state == SetupImport.State.RUNNING:
		cancel_import()
