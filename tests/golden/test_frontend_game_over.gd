extends GutTest
## GameOverPage agrees with the independent retail game-over facts in
## tests/golden/synthetic/frontend_game_over.json (tools/golden/make_golden_game_over.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_game_over.json"

var _document: Dictionary = {}


func before_all() -> void:
	_document = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))


static func _int(value: Variant) -> int:
	var number: float = value
	return int(number)


static func _ints(values: Variant) -> PackedInt32Array:
	var items: Array = values
	var result := PackedInt32Array()
	for value: Variant in items:
		result.append(_int(value))
	return result


static func _rows(value: Variant) -> Array:
	var rows: Array = value
	return rows


static func _flag(value: Variant) -> bool:
	var flag: bool = value
	return flag


static func _exit(value: Variant) -> int:
	if value == null:
		return -1
	var name_text: String = value
	return FrontEndFlow.event_from_name(name_text)


static func _check_row(test: GutTest, page: GameOverPage, row: Array, at: String) -> void:
	test.assert_eq(page.frame, _int(row[0]), at)
	test.assert_eq(page.units, _int(row[1]), at)
	test.assert_eq(page.view_rect(), Rect2i(_int(row[2]), _int(row[3]), _int(row[4]), _int(row[5])), at)
	test.assert_eq(page.view_width, _int(row[4]), at)
	test.assert_eq(page.view_height, _int(row[5]), at)
	test.assert_eq(page.sprite_grey, _int(row[6]), at)
	test.assert_eq(page.accepts_fire(), _flag(row[7]), at)
	test.assert_eq(page.overlay_visible(), _flag(row[8]), at)


func test_constants() -> void:
	var c: Dictionary = _document.constants
	assert_eq(GameOverPage.DURATION, _int(c.duration))
	assert_eq(GameOverPage.PREDELAY, _int(c.predelay))
	assert_eq(GameOverPage.FADE_TICKS, _int(c.fade_ticks))
	assert_eq(GameOverPage.FIRE_UNITS, _int(c.fire_units))
	assert_eq(GameOverPage.JINGLE_TRACK, _int(c.jingle_track))
	assert_eq(GameOverPage.SOUND_CROAK, _int(c.sound_croak))
	assert_eq(GameOverPage.DISPLAY_WIDTH, _int(c.display_width))
	assert_eq(GameOverPage.DISPLAY_HEIGHT, _int(c.display_height))
	var image: String = c.image
	assert_eq(GameOverPage.IMAGE, image)


func test_startup() -> void:
	var s: Dictionary = _document.startup
	for from_quit: bool in [false, true]:
		var page: GameOverPage = GameOverPage.create(from_quit)
		var at: String = "quit %s" % from_quit
		var view: PackedInt32Array = _ints(s.view)
		assert_eq(page.quit, from_quit, at)
		assert_eq(page.units, _int(s.units), at)
		assert_eq(page.frame, 0, at)
		assert_eq(page.shrink_steps, _int(s.shrink_steps), at)
		assert_eq(page.width_step, _int(s.width_step), at)
		assert_eq(page.view_rect(), Rect2i(view[0], view[1], view[2], view[3]), at)
		assert_eq(page.sprite_grey, _int(s.sprite_grey), at)
		assert_eq(page.startup_track(), _int(s.startup_track), at)
		assert_eq(page.mutes_effects(), _flag(s.mutes_effects), at)
		assert_eq(page.hides_hud(), _flag(s.hides_hud), at)
		assert_eq(page.exit_event, _exit(s.exit_event), at)
		assert_false(page.finished(), at)
		assert_eq(page.sounds, PackedInt32Array(), at)


func test_tick_table() -> void:
	var page: GameOverPage = GameOverPage.create(false)
	var rows: Array = _rows(_document.ticks)
	for row: Array in rows:
		var tick: int = _int(row[0])
		var returned: int = page.tick(false)
		var at: String = "tick %d" % tick
		_check_row(self, page, row, at)
		assert_eq(page.sounds, PackedInt32Array(), at)
		assert_eq(returned, page.exit_event, at)
		assert_eq(page.finished(), tick == rows.size(), at)


func test_traces() -> void:
	for trace: Dictionary in _rows(_document.traces):
		var label: String = trace.name
		var page: GameOverPage = GameOverPage.create(_flag(trace.quit))
		var fire_ticks: PackedInt32Array = _ints(trace.fire_ticks)
		var sounds_at: Dictionary = trace.sounds_at
		var exit_tick: int = _int(trace.exit_tick)
		var exit_event: int = _exit(trace.exit_event)
		var samples: Dictionary[int, Array] = {}
		for row: Array in _rows(trace.rows):
			samples[_int(row[0])] = row
		assert_true(samples.has(exit_tick), "%s samples its exit" % label)
		for tick: int in range(1, exit_tick + 1):
			var at: String = "%s tick %d" % [label, tick]
			var returned: int = page.tick(fire_ticks.has(tick))
			assert_eq(returned, page.exit_event, at)
			assert_eq(page.exit_event, exit_event if tick == exit_tick else -1, at)
			assert_eq(page.sounds, _ints(sounds_at.get(str(tick), [])), at)
			if samples.has(tick):
				_check_row(self, page, samples[tick], at)
		assert_eq(page.quit, _flag(trace.quit), label)
		assert_true(page.finished(), label)
		var frame: int = page.frame
		var rect: Rect2i = page.view_rect()
		var grey: int = page.sprite_grey
		var sounds: PackedInt32Array = page.sounds.duplicate()
		for _extra: int in 5:
			assert_eq(page.tick(true), exit_event, "%s inert after exit" % label)
			assert_eq(page.frame, frame, "%s inert after exit" % label)
			assert_eq(page.view_rect(), rect, "%s inert after exit" % label)
			assert_eq(page.sprite_grey, grey, "%s inert after exit" % label)
			assert_eq(page.sounds, sounds, "%s inert after exit" % label)
