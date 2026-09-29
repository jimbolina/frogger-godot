extends GutTest
## LegacyConfigParser follows FrogLord's older reader rule for rule.


func _parse(text: String) -> FrogLordConfig:
	var parser := LegacyConfigParser.new()
	var config: FrogLordConfig = parser.parse(text, "root")
	assert_eq(parser.error, "", "parses without error")
	return config


func test_keys_values_and_comments() -> void:
	var c: FrogLordConfig = _parse("# header\nname=PC Retail (x) # title\nmwiOffset=0x8AE20\nmwiLength=48840\n")
	assert_eq(c.get_string("name"), "PC Retail (x)", "comment and trailing space removed, inner spaces kept")
	assert_eq(c.get_int("mwiOffset"), 0x8AE20)
	assert_eq(c.get_int("mwiLength"), 48840)
	assert_eq(c.keys(), PackedStringArray(["name", "mwiOffset", "mwiLength"]))


func test_hash_has_no_escape_in_the_old_format() -> void:
	var c: FrogLordConfig = _parse("colour=##FF00FF\n")
	assert_eq(c.get_string("colour"), "")


func test_text_lines_and_sticky_text_mode() -> void:
	var c: FrogLordConfig = _parse("a=1\nGEN_FLY_BUZZ\nb=2\nGEN FROG\n")
	assert_true(c.has_key("a"))
	assert_false(c.has_key("b"), "after the first text line, pairs become text")
	assert_eq(c.text, PackedStringArray(["GEN_FLY_BUZZ", "b=2", "GEN FROG"]))


func test_space_in_key_makes_text() -> void:
	var c: FrogLordConfig = _parse("some key=value\n")
	assert_eq(c.text, PackedStringArray(["some key=value"]))


func test_leading_whitespace_is_kept() -> void:
	var c: FrogLordConfig = _parse("  indented=1\n")
	assert_false(c.has_key("indented"), "the kept leading spaces put a space in the key")
	assert_eq(c.text, PackedStringArray(["  indented=1"]))


func test_empty_line_marker() -> void:
	var c: FrogLordConfig = _parse("FIRST\n``\nTHIRD\n")
	assert_eq(c.text, PackedStringArray(["FIRST", "", "THIRD"]))


func test_nested_sections() -> void:
	var c: FrogLordConfig = _parse("top=1\n[Fixed]\nA.VLO\n[[General]]\nB.VLO\n[[[Start]]]\nC.VLO\n[[Other]]\nD.VLO\n[Second]\nk=v\n")
	assert_eq(c.children.size(), 2)
	var fixed: FrogLordConfig = c.get_child("Fixed")
	assert_eq(fixed.text, PackedStringArray(["A.VLO"]))
	assert_eq(fixed.children.size(), 2)
	assert_eq(fixed.get_child("General").get_child("Start").text, PackedStringArray(["C.VLO"]))
	assert_eq(fixed.get_child("Other").text, PackedStringArray(["D.VLO"]))
	assert_eq(c.get_child("Second").get_string("k"), "v")
	assert_eq(fixed.get_child("General").layer, 2)


func test_repeated_key_overwrites() -> void:
	var c: FrogLordConfig = _parse("k=1\nk=2\n")
	assert_eq(c.get_int("k"), 2)


func test_skipping_a_level_is_an_error() -> void:
	var parser := LegacyConfigParser.new()
	assert_null(parser.parse("[[Deep]]\n", "root"))
	assert_string_contains(parser.error, "layer")


func test_unbalanced_brackets_are_an_error() -> void:
	var parser := LegacyConfigParser.new()
	assert_null(parser.parse("[A]]\n", "root"))
	assert_string_contains(parser.error, "unbalanced")


func test_windows_line_endings() -> void:
	var c: FrogLordConfig = _parse("a=1\r\n[S]\r\nX\r\n")
	assert_eq(c.get_int("a"), 1)
	assert_eq(c.get_child("S").text, PackedStringArray(["X"]))


## Decodes [param text]; -999 stands for "not a number" so results stay typed.
func _dec(text: String) -> int:
	var parsed: Variant = FrogLordConfig.decode_integer(text)
	if parsed is int:
		var number: int = parsed
		return number
	return -999


func test_integer_decode_follows_java() -> void:
	assert_eq(_dec("0x070100"), 0x70100)
	assert_eq(_dec("0X1f"), 31)
	assert_eq(_dec("#10"), 16)
	assert_eq(_dec("010"), 8, "a leading zero means octal")
	assert_eq(_dec("0"), 0)
	assert_eq(_dec("-12"), -12)
	assert_eq(_dec("+7"), 7)
	assert_eq(_dec("09"), -999, "9 is not an octal digit")
	assert_eq(_dec(""), -999)
	assert_eq(_dec("12a"), -999)
	assert_eq(_dec("0x"), -999)
	assert_eq(_dec("--1"), -999)


func test_typed_getters() -> void:
	var c: FrogLordConfig = _parse("flag=TRUE\nlist=15,3, 7\nbad=zz\n")
	assert_true(c.get_bool("flag"))
	assert_false(c.get_bool("missing"))
	assert_eq(c.get_int_array("list"), PackedInt64Array([15, 3, 7]))
	assert_eq(c.get_int("bad", -5), -5)
	assert_false(c.has_valid_int("bad"))
	assert_eq(c.get_string("missing", "fallback"), "fallback")
