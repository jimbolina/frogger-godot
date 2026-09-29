extends GutTest
## FrogLordExeTrailer on hand-built executables.

const BUILD_INFO: String = "[BuildInfo]\ngameType=frogger\ngameVersion=pc-retail-v3.0e\nfrogLordVersion=7\n"


## A fake "program": an MZ header and some filler.
static func fake_program(size: int) -> PackedByteArray:
	var exe := PackedByteArray()
	exe.resize(size)
	exe[0] = 0x4D # 'M'
	exe[1] = 0x5A # 'Z'
	for i: int in range(2, size):
		exe[i] = (i * 7) & 0xFF
	return exe


## [param program] with a FrogLord trailer carrying [param text].
static func with_trailer(program: PackedByteArray, text: String, format: int = 0) -> PackedByteArray:
	var exe: PackedByteArray = program.duplicate()
	exe.append_array(FrogLordExeTrailer.build_footer(text, program.size(), format))
	return exe


func test_plain_executable_has_no_trailer() -> void:
	assert_false(FrogLordExeTrailer.is_present(fake_program(64)))
	assert_null(FrogLordExeTrailer.read(fake_program(64)))


func test_reads_build_info() -> void:
	var exe: PackedByteArray = with_trailer(fake_program(100), BUILD_INFO)
	assert_true(FrogLordExeTrailer.is_present(exe))
	var t: FrogLordExeTrailer = FrogLordExeTrailer.read(exe)
	assert_eq(t.error, "")
	assert_eq(t.format_version, 0)
	assert_eq(t.original_exe_length, 100)
	assert_eq(t.game_type, "frogger")
	assert_eq(t.game_version, "pc-retail-v3.0e")
	assert_eq(t.froglord_version, 7)


func test_footer_layout_matches_froglord() -> void:
	var footer: PackedByteArray = FrogLordExeTrailer.build_footer("ab", 0x01020304)
	assert_eq(footer, PackedByteArray([0x61, 0x62, 0x00, 0x00, 0x04, 0x03, 0x02, 0x01,
		0x46, 0x52, 0x4F, 0x47, 0x4C, 0x4F, 0x52, 0x44]))


func test_newer_format_is_refused_clearly() -> void:
	var t: FrogLordExeTrailer = FrogLordExeTrailer.read(with_trailer(fake_program(64), BUILD_INFO, 1))
	assert_string_contains(t.error, "newer FrogLord")


func test_bad_original_length() -> void:
	var exe: PackedByteArray = fake_program(64)
	exe.append_array(FrogLordExeTrailer.build_footer(BUILD_INFO, 5000))
	assert_string_contains(FrogLordExeTrailer.read(exe).error, "does not fit")


func test_missing_build_info_section() -> void:
	var t: FrogLordExeTrailer = FrogLordExeTrailer.read(with_trailer(fake_program(64), "gameType=frogger\n"))
	assert_string_contains(t.error, "BuildInfo")


func test_not_a_windows_executable() -> void:
	var program: PackedByteArray = fake_program(64)
	program[0] = 0
	assert_string_contains(FrogLordExeTrailer.read(with_trailer(program, BUILD_INFO)).error, "MZ")
