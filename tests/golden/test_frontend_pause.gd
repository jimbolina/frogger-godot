extends GutTest
## PausePage, PauseCheats and LevelProgress agree with the independent frozen-C and retail-exe
## pause facts in tests/golden/synthetic/frontend_pause.json (tools/golden/make_golden_pause.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_pause.json"

var _document: Dictionary = {}


func before_all() -> void:
	_document = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))


static func _int(value: Variant) -> int:
	var number: float = value
	return int(number)


static func _rows(value: Variant) -> Array:
	var rows: Array = value
	return rows


static func _text(value: Variant) -> String:
	var text: String = value
	return text


static func _sprite(value: Variant) -> PausePage.Sprite:
	return PausePage.Sprite.keys().find(_text(value)) as PausePage.Sprite


static func _events(value: Variant) -> Array[PausePage.Event]:
	var events: Array[PausePage.Event] = []
	for name: Variant in _rows(value):
		events.append(PausePage.Event.keys().find(_text(name)) as PausePage.Event)
	return events


static func _buttons(scene: Dictionary, tick: int) -> PausePage.Buttons:
	var inputs: Dictionary = scene.inputs
	var keys: Array = _rows(inputs.get(str(tick), []))
	var buttons := PausePage.Buttons.new()
	buttons.escape = keys.has("escape")
	buttons.up = keys.has("up")
	buttons.down = keys.has("down")
	buttons.left = keys.has("left")
	buttons.right = keys.has("right")
	buttons.fire_released = keys.has("fire")
	return buttons


func test_constants() -> void:
	var c: Dictionary = _document.constants
	assert_eq(PausePage.FADE_STEP, _int(c.fade_step))
	assert_eq(PausePage.FADE_END, _int(c.fade_end))
	assert_eq(PausePage.HOP_SOUND, _int(c.hop_sound))
	assert_eq(PausePage.CROAK_SOUND, _int(c.croak_sound))
	assert_eq(PausePage.PAUSED_Y, _int(c.paused_y))
	assert_eq(PausePage.CONTINUE_Y, _int(c.continue_y))
	assert_eq(PausePage.QUIT_Y, _int(c.quit_y))
	assert_eq(PausePage.YES_NO_Y, _int(c.yes_no_y))
	assert_eq(PausePage.YES_NO_OFFSET, _int(c.yes_no_offset))
	assert_eq(PausePage.QUIT_YES, _int(c.quit_yes))
	assert_eq(PausePage.QUIT_NO, _int(c.quit_no))
	assert_eq(PausePage.CONTINUE_SELECTED, _int(c.continue_selected))
	assert_eq(PausePage.QUIT_SELECTED, _int(c.quit_selected))


func test_images() -> void:
	var images: Dictionary = _document.images
	assert_eq(PausePage.PAUSED_IMAGE, _text(images.PAUSED))
	assert_eq(PausePage.CONTINUE_IMAGE, _text(images.CONTINUE))
	assert_eq(PausePage.QUIT_IMAGE, _text(images.QUIT))
	assert_eq(PausePage.YES_IMAGE, _text(images.YES))
	assert_eq(PausePage.NO_IMAGE, _text(images.NO))


func test_glow_and_positions() -> void:
	for row: Array in _rows(_document.glow):
		assert_eq(PausePage.glow(_int(row[0])), _int(row[1]), "frame %d" % _int(row[0]))
	for row: Dictionary in _rows(_document.positions):
		var sprite: PausePage.Sprite = _sprite(row.sprite)
		var at: String = "%s width %d" % [_text(row.sprite), _int(row.width)]
		assert_eq(PausePage.sprite_x(_int(row.width), sprite), _int(row.x), at)
		assert_eq(PausePage.sprite_y(sprite), _int(row.y), at)


func test_scene_traces() -> void:
	for scene: Dictionary in _rows(_document.scenes):
		var label: String = scene.name
		var page: PausePage = PausePage.create(_int(scene.sound_volume))
		assert_eq(page.startup_events(), _events(scene.startup_events), label)
		var trace: Array = _rows(scene.trace)
		assert_eq(trace.size(), _int(scene.ticks), label)
		var tick: int = 0
		for row: Array in trace:
			tick += 1
			var at: String = "%s tick %d" % [label, tick]
			var events: Array[PausePage.Event] = page.tick(_buttons(scene, tick))
			assert_eq(page.frame, _int(row[0]), at)
			assert_eq(_text(PausePage.Mode.keys()[page.mode]), _text(row[1]), at)
			assert_eq(_text(PausePage.MenuMode.keys()[page.menu_mode]), _text(row[2]), at)
			assert_eq(page.fade_level, _int(row[3]), at)
			assert_eq(page.volume, _int(row[4]), at)
			assert_eq(page.selection, _int(row[5]), at)
			assert_eq(page.quit_selection, _int(row[6]), at)
			assert_eq(page.glowing_sprite(), _sprite(row[7]), at)
			assert_eq(events, _events(row[8]), at)
			assert_eq(page.active(), _text(row[1]) != "NO_PAUSE", at)


func test_scene_sprites() -> void:
	for scene: Dictionary in _rows(_document.scenes):
		var label: String = scene.name
		for shot: Dictionary in _rows(scene.sprites_at):
			var frame: int = _int(shot.frame)
			var page: PausePage = PausePage.create(_int(scene.sound_volume))
			for tick: int in range(1, frame + 1):
				page.tick(_buttons(scene, tick))
			var widths: Dictionary = shot.widths
			var images: Dictionary[PausePage.Sprite, String] = {
				PausePage.Sprite.PAUSED: PausePage.PAUSED_IMAGE,
				PausePage.Sprite.CONTINUE: PausePage.CONTINUE_IMAGE,
				PausePage.Sprite.QUIT: PausePage.QUIT_IMAGE,
				PausePage.Sprite.YES: PausePage.YES_IMAGE,
				PausePage.Sprite.NO: PausePage.NO_IMAGE,
			}
			var shown: Array[PausePage.Sprite] = []
			if page.shows_sprites():
				shown.append_array([PausePage.Sprite.PAUSED, PausePage.Sprite.CONTINUE, PausePage.Sprite.QUIT])
			if page.shows_quit():
				shown.append_array([PausePage.Sprite.YES, PausePage.Sprite.NO])
			var actual := PackedStringArray()
			for sprite: PausePage.Sprite in shown:
				var image: String = images[sprite]
				actual.append("%s %s@%d,%d" % [PausePage.Sprite.keys()[sprite], image,
					PausePage.sprite_x(_int(widths[image]), sprite), PausePage.sprite_y(sprite)])
			var expected := PackedStringArray()
			for row: Dictionary in _rows(shot.sprites):
				expected.append("%s %s@%d,%d" % [_text(row.sprite), _text(row.image), _int(row.x), _int(row.y)])
			assert_eq(actual, expected, "%s frame %d" % [label, frame])


static func _ints(value: Variant) -> PackedInt32Array:
	var ints := PackedInt32Array()
	for number: Variant in _rows(value):
		ints.append(_int(number))
	return ints


static func _cheat_names(fired: Array[int]) -> PackedStringArray:
	var names := PackedStringArray()
	for cheat: int in fired:
		names.append(_text(PauseCheats.Cheat.keys()[cheat]))
	return names


static func _strings(value: Variant) -> PackedStringArray:
	var names := PackedStringArray()
	for name: Variant in _rows(value):
		names.append(_text(name))
	return names


static func _stack_rows(value: Variant) -> Array[LevelStack.Row]:
	var rows: Array[LevelStack.Row] = []
	for row: Dictionary in _rows(value):
		rows.append(LevelStack.Row.new(_int(row.level), _int(row.world), _int(row.stack), _int(row.theme),
			_int(row.local), _int(row.levels_in_world)))
	return rows


func _cheats() -> Dictionary:
	return _document.cheats


func test_cheat_sequences() -> void:
	var cheats: Dictionary = _cheats()
	assert_eq(PauseCheats.SPACE, _int(cheats.space))
	var gate_keys: PackedInt32Array = _ints(cheats.gate_keys)
	for scancode: int in 256:
		assert_eq(PauseCheats.gates(scancode), gate_keys.has(scancode), "0x%02x" % scancode)
	var sequences: Array = _rows(cheats.sequences)
	assert_eq(PauseCheats.SEQUENCES.size(), sequences.size())
	for index: int in sequences.size():
		var row: Dictionary = sequences[index]
		assert_eq(_text(PauseCheats.Cheat.keys()[index]), _text(row.cheat))
		assert_eq(PauseCheats.SEQUENCES[index], _ints(row.scancodes), _text(row.phrase))


func test_cheat_events() -> void:
	var events: Dictionary = _cheats().events
	for index: int in PauseCheats.SEQUENCES.size():
		var name: String = PauseCheats.Cheat.keys()[index]
		var page: PausePage = PausePage.create(5)
		page.cheats = PauseCheats.new()
		for _tick: int in 9:
			page.tick(PausePage.Buttons.new())
		var fired: Array[PausePage.Event] = []
		for key: int in PauseCheats.SEQUENCES[index]:
			page.cheats.note_key_down()
			var buttons := PausePage.Buttons.new()
			buttons.keys_down = PackedInt32Array([key])
			fired.append_array(page.tick(buttons))
		assert_eq(fired, _events(events[name]), name)


func test_cheat_traces() -> void:
	for trace: Dictionary in _rows(_cheats().traces):
		var label: String = trace.name
		var cheats := PauseCheats.new()
		var step: int = 0
		for row: Dictionary in _rows(trace.steps):
			step += 1
			var at: String = "%s step %d" % [label, step]
			if row.gate:
				cheats.note_key_down()
			var fired: Array[int] = cheats.check(_ints(row.down))
			assert_eq(_cheat_names(fired), _strings(row.fired), at)
			assert_eq(cheats.cursors, _ints(row.cursors), at)
			assert_false(cheats.gate, at)


func test_cheat_scenes() -> void:
	for scene: Dictionary in _rows(_cheats().scenes):
		var label: String = scene.name
		var cheats := PauseCheats.new()
		var page_index: int = 0
		for page_data: Dictionary in _rows(scene.pages):
			page_index += 1
			var page: PausePage = PausePage.create(_int(scene.sound_volume))
			page.cheats = cheats
			var keys: Dictionary = page_data.keys
			var trace: Array = _rows(page_data.trace)
			assert_eq(trace.size(), _int(page_data.ticks), label)
			var tick: int = 0
			for row: Array in trace:
				tick += 1
				var at: String = "%s page %d tick %d" % [label, page_index, tick]
				var buttons: PausePage.Buttons = _buttons(page_data, tick)
				buttons.arcade = scene.arcade
				var key: Dictionary = keys.get(str(tick), {})
				if key.get("gate", false):
					cheats.note_key_down()
				buttons.keys_down = _ints(key.get("down", []))
				var events: Array[PausePage.Event] = page.tick(buttons)
				assert_eq(page.frame, _int(row[0]), at)
				assert_eq(_text(PausePage.Mode.keys()[page.mode]), _text(row[1]), at)
				assert_eq(events, _events(row[2]), at)
				assert_eq(cheats.cursors, _ints(row[3]), at)
				var gate: bool = row[4]
				assert_eq(cheats.gate, gate, at)


func test_unlock_cases() -> void:
	var unlock: Dictionary = _cheats().unlock
	var stack: LevelStack = LevelStack.create(_stack_rows(unlock.arcade_rows), _stack_rows(unlock.race_rows))
	var ordered: PackedInt32Array = PackedInt32Array()
	for row: Array in _rows(unlock.zone_unlock):
		ordered.append(_int(row[1]))
	assert_eq(ordered, PackedInt32Array([0, 2, 3, 42, 43, 44, 45, 36, 37, 38, 39, 40, 6, 7, 8, 9, 10, 18]))
	for case: Dictionary in _rows(unlock.cases):
		var label: String = case.name
		var progress: LevelProgress = LevelProgress.create(stack)
		for op: Array in _rows(case.setup):
			match _text(op[0]):
				"complete":
					progress.complete_level(_int(op[1]))
				"open_if_closed":
					progress.open_level_if_closed(_int(op[1]))
				"set_row":
					progress.arcade_flags[_int(op[1])] = _int(op[2])
		assert_eq(progress.arcade_levels, _ints(case.levels), label)
		assert_eq(progress.arcade_flags, _ints(case.flags), label)
		assert_eq(progress.race_flags, _ints(case.race_flags), label)
		var zones: LevelProgress = progress.copy()
		zones.unlock_all_zones()
		assert_eq(zones.arcade_flags, _ints(case.after_all_zones), "%s all zones" % label)
		var levels: LevelProgress = progress.copy()
		levels.unlock_all_levels()
		assert_eq(levels.arcade_flags, _ints(case.after_all_levels), "%s all levels" % label)
		zones.unlock_all_levels()
		assert_eq(zones.arcade_flags, _ints(case.after_both), "%s both" % label)
		assert_eq(zones.race_flags, _ints(case.race_flags), "%s race rows untouched" % label)
		assert_eq(zones.arcade_levels, _ints(case.levels), "%s rows untouched" % label)
