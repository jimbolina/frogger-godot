extends GutTest
## The pause-cheat dispatcher against the retail PC executable (0x0042fda0).

const N: int = 0x31
const O: int = 0x18
const M: int = 0x32
const R: int = 0x13
const E: int = 0x12
const T: int = 0x14
const X: int = 0x2D
const SPACE: int = PauseCheats.SPACE


static func _type(cheats: PauseCheats, sequence: PackedInt32Array) -> Array[int]:
	var fired: Array[int] = []
	for key: int in sequence:
		cheats.note_key_down()
		fired.append_array(cheats.check(PackedInt32Array([key])))
	return fired


func test_sequences_spell_the_phrases() -> void:
	assert_eq(PauseCheats.SEQUENCES.size(), 4)
	assert_eq(PauseCheats.SEQUENCES[PauseCheats.Cheat.INFINITE_LIVES].size(), 19)
	assert_eq(PauseCheats.SEQUENCES[PauseCheats.Cheat.ALL_ZONES].size(), 25)
	assert_eq(PauseCheats.SEQUENCES[PauseCheats.Cheat.ALL_LEVELS].size(), 32)
	assert_eq(PauseCheats.SEQUENCES[PauseCheats.Cheat.TIMEOUT_DEATHS].size(), 29)
	for sequence: PackedInt32Array in PauseCheats.SEQUENCES:
		for key: int in sequence:
			assert_true(PauseCheats.gates(key), "0x%02x gates" % key)


func test_gates_are_the_letters_and_space() -> void:
	var gating: int = 0
	for scancode: int in 256:
		if PauseCheats.gates(scancode):
			gating += 1
	assert_eq(gating, 27)
	assert_true(PauseCheats.gates(0x10))
	assert_true(PauseCheats.gates(0x26))
	assert_true(PauseCheats.gates(0x2C))
	assert_true(PauseCheats.gates(SPACE))
	assert_false(PauseCheats.gates(0x01), "Escape")
	assert_false(PauseCheats.gates(0x1C), "Return")
	assert_false(PauseCheats.gates(0x1D), "Left Ctrl")
	assert_false(PauseCheats.gates(0x3A), "Caps Lock")
	assert_false(PauseCheats.gates(0x02), "1")


func test_fresh_dispatcher_is_closed() -> void:
	var cheats := PauseCheats.new()
	assert_false(cheats.gate)
	assert_eq(cheats.cursors, PackedInt32Array([0, 0, 0, 0]))


func test_each_phrase_fires_its_cheat_once() -> void:
	for cheat: int in PauseCheats.Cheat.values():
		var cheats := PauseCheats.new()
		var sequence: PackedInt32Array = PauseCheats.SEQUENCES[cheat]
		var fired: Array[int] = _type(cheats, sequence.slice(0, sequence.size() - 1))
		assert_eq(fired, [] as Array[int], "%d waits for the last key" % cheat)
		cheats.note_key_down()
		assert_eq(cheats.check(PackedInt32Array([sequence[sequence.size() - 1]])), [cheat] as Array[int])
		assert_eq(cheats.cursors[cheat], 0, "%d resets after firing" % cheat)
		assert_false(cheats.gate)


func test_no_gate_changes_nothing() -> void:
	var cheats := PauseCheats.new()
	assert_eq(cheats.check(PackedInt32Array([N])), [] as Array[int])
	assert_eq(cheats.cursors, PackedInt32Array([0, 0, 0, 0]))
	_type(cheats, PackedInt32Array([N, O]))
	assert_eq(cheats.check(PackedInt32Array([X])), [] as Array[int])
	assert_eq(cheats.cursors, PackedInt32Array([2, 0, 0, 2]), "Without the gate the cursors stay")


func test_shared_prefix_advances_both_sequences_until_they_part() -> void:
	var cheats := PauseCheats.new()
	_type(cheats, PackedInt32Array([N, O, SPACE, M, O, R, E, SPACE]))
	assert_eq(cheats.cursors, PackedInt32Array([8, 0, 0, 8]))
	_type(cheats, PackedInt32Array([T]))
	assert_eq(cheats.cursors, PackedInt32Array([0, 0, 0, 9]), "T is TIMEOUT's key; ROAD resets")


func test_wrong_key_resets_without_retesting_as_the_first_element() -> void:
	var cheats := PauseCheats.new()
	_type(cheats, PackedInt32Array([N, O, SPACE]))
	_type(cheats, PackedInt32Array([N]))
	assert_eq(cheats.cursors[PauseCheats.Cheat.INFINITE_LIVES], 0, "N at element 3 only resets")
	_type(cheats, PackedInt32Array([N]))
	assert_eq(cheats.cursors[PauseCheats.Cheat.INFINITE_LIVES], 1)


func test_held_keys_count_as_down() -> void:
	var cheats := PauseCheats.new()
	cheats.note_key_down()
	cheats.check(PackedInt32Array([N]))
	cheats.note_key_down()
	cheats.check(PackedInt32Array([N, O]))
	assert_eq(cheats.cursors[PauseCheats.Cheat.INFINITE_LIVES], 2, "O pressed while N stays held")
	cheats.note_key_down()
	cheats.check(PackedInt32Array([O, X]))
	assert_eq(cheats.cursors[PauseCheats.Cheat.INFINITE_LIVES], 0, "Space is not down")
	_type(cheats, PackedInt32Array([T, O]))
	cheats.note_key_down()
	cheats.check(PackedInt32Array([O, X]))
	assert_eq(cheats.cursors[PauseCheats.Cheat.ALL_LEVELS], 0, "T is not element 0 of WAY")
	_type(cheats, PackedInt32Array([0x11, 0x1E, 0x15, SPACE, T, O]))
	cheats.note_key_down()
	cheats.check(PackedInt32Array([O, X]))
	assert_eq(cheats.cursors[PauseCheats.Cheat.ALL_LEVELS], 7, "The held O is TOO's second O; X is not tested")


func test_stale_gate_with_nothing_down_resets_every_cursor() -> void:
	var cheats := PauseCheats.new()
	_type(cheats, PackedInt32Array([N, O]))
	cheats.note_key_down()
	assert_eq(cheats.check(PackedInt32Array()), [] as Array[int])
	assert_eq(cheats.cursors, PackedInt32Array([0, 0, 0, 0]))
	assert_false(cheats.gate)


func test_reset_clears_gate_and_cursors() -> void:
	var cheats := PauseCheats.new()
	_type(cheats, PackedInt32Array([N, O]))
	cheats.note_key_down()
	cheats.reset()
	assert_false(cheats.gate)
	assert_eq(cheats.cursors, PackedInt32Array([0, 0, 0, 0]))
