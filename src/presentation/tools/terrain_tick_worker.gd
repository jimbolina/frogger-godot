class_name TerrainTickWorker
extends RefCounted
## Runs one exclusively owned terrain transaction at a time, without touching scene objects.
## The host schedules input and drains or closes the worker before replacing its run.

var _run: GameplayRun
var _thread := Thread.new()
var _wake := Semaphore.new()
var _done := Semaphore.new()
var _mutex := Mutex.new()
var _command: TickCommand
var _result: TickResult
var _stopping: bool = false
var pending: bool = false
var last_tick_usec: int = 0

## Starts an idle worker; the caller must stop accessing the run until close.
func start(run: GameplayRun) -> Error:
	_run = run
	return _thread.start(_work)

## Transfers a command to the idle worker. A second submission is rejected.
func submit(command: TickCommand) -> bool:
	if pending or not _thread.is_started():
		return false
	_mutex.lock()
	_command = command.copy()
	_mutex.unlock()
	pending = true
	_wake.post()
	return true

## Returns a detached completed result without waiting for an unfinished tick.
func poll() -> TickResult:
	if not pending or not _done.try_wait():
		return null
	return _take()

## Waits for an outstanding tick before explicit stepping, pause or replacement.
func finish() -> TickResult:
	if not pending:
		return null
	_done.wait()
	return _take()

## Joins the thread before releasing its exclusively owned run.
func close() -> void:
	if not _thread.is_started():
		return
	finish()
	_mutex.lock()
	_stopping = true
	_mutex.unlock()
	_wake.post()
	_thread.wait_to_finish()
	_run = null

func _take() -> TickResult:
	_mutex.lock()
	var result: TickResult = _result
	_result = null
	_mutex.unlock()
	pending = false
	return result

func _work() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		var stopping: bool = _stopping
		var command: TickCommand = _command
		_mutex.unlock()
		if stopping:
			return
		var started: int = Time.get_ticks_usec()
		var result: TickResult = _run.step(command, false)
		var duration: int = Time.get_ticks_usec() - started
		_mutex.lock()
		_result = result
		last_tick_usec = duration
		_mutex.unlock()
		_done.post()
