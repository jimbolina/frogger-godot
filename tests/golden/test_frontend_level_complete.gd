extends GutTest
## LevelCompletePage and LevelCompleteLayout agree with the independent frozen-C level-complete
## facts in tests/golden/synthetic/frontend_level_complete.json (tools/make_golden_level_complete.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_level_complete.json"

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


static func _create(scene: Dictionary) -> LevelCompletePage:
	var variant_name: String = scene.variant
	var variant: LevelCompletePage.Kind = (
		LevelCompletePage.Kind.keys().find(variant_name) as LevelCompletePage.Kind)
	return LevelCompletePage.create(variant, _int(scene.next_level), _ints(scene.checkpoint_ticks),
		_int(scene.level_score), _flag(scene.show_gold_frog))


static func _keys(scene: Dictionary, tick: int) -> PackedStringArray:
	var inputs: Dictionary = scene.inputs
	var keys := PackedStringArray()
	for key: Variant in _rows(inputs.get(str(tick), [])):
		var text: String = key
		keys.append(text)
	return keys


static func _tick(page: LevelCompletePage, scene: Dictionary, tick: int) -> int:
	var keys: PackedStringArray = _keys(scene, tick)
	return page.tick(keys.has("fire"), keys.has("back"))


func test_constants() -> void:
	var c: Dictionary = _document.constants
	assert_eq(LevelCompletePage.START_UNITS, _int(c.start_units))
	assert_eq(LevelCompletePage.UNIT_TICKS, _int(c.unit_ticks))
	assert_eq(LevelCompletePage.LAST_UNITS, _int(c.last_units))
	assert_eq(LevelCompletePage.FIRE_UNITS, _int(c.fire_units))
	assert_eq(LevelCompletePage.BLINK_BIT, _int(c.blink_bit))
	assert_eq(LevelCompletePage.SOUND_LEVEL_COMPLETE, _int(c.sound_level_complete))
	assert_eq(LevelCompletePage.SOUND_CROAK, _int(c.sound_croak))


func test_checkpoint_seconds() -> void:
	for row: Dictionary in _rows(_document.seconds):
		var ticks: int = _int(row.ticks)
		assert_eq(HighScoreBoard.checkpoint_seconds(ticks), _int(row.seconds), "ticks %d" % ticks)


func test_centring_and_digits() -> void:
	for row: Dictionary in _rows(_document.centring):
		assert_eq(LevelCompleteLayout.centred_x(_int(row.width)), _int(row.x), "width %d" % _int(row.width))
	for row: Dictionary in _rows(_document.digits):
		var text: String = row.text
		assert_eq(LevelCompleteLayout.digits(_int(row.value), _int(row.count)), text)


func test_animation_cels() -> void:
	for row: Dictionary in _rows(_document.frames):
		var frame: int = _int(row.frame)
		var checkpoint_name: String = row.checkpoint_image
		var gold_name: String = row.gold_image
		assert_eq(LevelCompleteLayout.checkpoint_image(_int(row.checkpoint), frame), checkpoint_name)
		assert_eq(LevelCompleteLayout.gold_image(frame), gold_name)


func test_scene_traces() -> void:
	for scene: Dictionary in _rows(_document.scenes):
		var label: String = scene.name
		var page: LevelCompletePage = _create(scene)
		assert_eq(page.checkpoint_seconds, _ints(scene.checkpoint_seconds), label)
		assert_eq(page.total_seconds, _int(scene.total_seconds), label)
		assert_eq(page.startup_sounds(), _ints(scene.startup_sounds), label)
		assert_eq(page.pauses_music(), _flag(scene.pauses_music), label)
		assert_eq(page.shows_prompt(), _flag(scene.shows_prompt), label)
		var trace: Array = _rows(scene.trace)
		var tick: int = 0
		for row: Array in trace:
			tick += 1
			var at: String = "%s tick %d" % [label, tick]
			var returned: int = _tick(page, scene, tick)
			assert_eq(page.frame, _int(row[0]), at)
			assert_eq(page.units, _int(row[1]), at)
			assert_eq(page.ticks, _int(row[2]), at)
			assert_eq(page.accepts_fire(), _flag(row[3]), at)
			assert_eq(page.press_fire_visible, _flag(row[4]), at)
			assert_eq(page.sounds, _ints(row[5]), at)
			assert_eq(page.exit_event, _exit(row[6]), at)
			assert_eq(returned, page.exit_event, at)
			assert_eq(page.finished(), row[6] != null, at)
		var exit_event: int = page.exit_event
		if exit_event >= 0:
			var frame: int = page.frame
			var sounds: PackedInt32Array = page.sounds.duplicate()
			for _extra: int in 5:
				assert_eq(page.tick(true, true), exit_event, "%s inert after exit" % label)
				assert_eq(page.frame, frame, "%s inert after exit" % label)
				assert_eq(page.sounds, sounds, "%s inert after exit" % label)
		else:
			assert_eq(trace.size(), _int(scene.ticks), "%s runs every tick" % label)
		if scene.has("no_exit_after"):
			var limit: int = _int(scene.no_exit_after)
			var exits: int = 0
			while page.frame < limit and not page.finished():
				if _tick(page, scene, page.frame + 1) != -1:
					exits += 1
			assert_eq(exits, 0, "%s never exits" % label)
			assert_eq(page.frame, limit, "%s never exits" % label)
			assert_eq(page.exit_event, -1, "%s never exits" % label)
			assert_eq(page.units, LevelCompletePage.LAST_UNITS, "%s holds the last unit" % label)


func test_scene_sprites() -> void:
	for scene: Dictionary in _rows(_document.scenes):
		var label: String = scene.name
		for shot: Dictionary in _rows(scene.sprites_at):
			var frame: int = _int(shot.frame)
			var page: LevelCompletePage = _create(scene)
			for tick: int in range(1, frame + 1):
				assert_eq(_tick(page, scene, tick), page.exit_event, "%s frame %d" % [label, tick])
			var widths: Dictionary[String, int] = {}
			var given: Dictionary = shot.widths
			for key: Variant in given:
				var image_name: String = key
				widths[image_name] = _int(given[key])
			var expected := PackedStringArray()
			for sprite: Dictionary in _rows(shot.sprites):
				expected.append("%s@%d,%d" % [sprite.image, _int(sprite.x), _int(sprite.y)])
			var actual := PackedStringArray()
			for sprite: LevelCompleteLayout.Sprite in LevelCompleteLayout.sprites(page, widths):
				actual.append("%s@%d,%d" % [sprite.image, sprite.at.x, sprite.at.y])
			assert_eq(actual, expected, "%s frame %d" % [label, frame])
