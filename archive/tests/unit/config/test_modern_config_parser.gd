extends GutTest
## ModernConfigParser follows FrogLord's newer reader (used for executable build information).


func _parse(text: String) -> FrogLordConfig:
	var parser := ModernConfigParser.new()
	var config: FrogLordConfig = parser.parse(text, "root")
	assert_eq(parser.error, "", "parses without error")
	return config


func test_build_info_section() -> void:
	var c: FrogLordConfig = _parse("[BuildInfo]\ngameType=frogger\ngameVersion=pc-retail-v3.0e\nfrogLordVersion=12\n")
	var info: FrogLordConfig = c.get_child("BuildInfo")
	assert_not_null(info)
	assert_eq(info.get_string("gameType"), "frogger")
	assert_eq(info.get_string("gameVersion"), "pc-retail-v3.0e")
	assert_eq(info.get_int("frogLordVersion"), 12)


func test_lines_are_trimmed_and_comments_split() -> void:
	var c: FrogLordConfig = _parse("   key=value   # comment\n")
	assert_eq(c.get_string("key"), "value")


func test_double_hash_is_a_literal_hash() -> void:
	var c: FrogLordConfig = _parse("colour=##FF00FF # real comment\n")
	assert_eq(c.get_string("colour"), "#FF00FF")


func test_null_values() -> void:
	var c: FrogLordConfig = _parse("a=null\nb=\"null\"\n")
	assert_true(c.has_key("a"))
	assert_eq(c.get_string("a", "none"), "none", "null has no text")
	assert_eq(c.get_string("b"), "null")


func test_escaped_key_characters() -> void:
	var c: FrogLordConfig = _parse("my\\ key\\=x=5\n")
	assert_eq(c.get_int("my key=x"), 5)


func test_space_before_equals_makes_text_and_blank_lines_are_text() -> void:
	var c: FrogLordConfig = _parse("not a key=1\n\nk=2\n")
	assert_eq(c.text, PackedStringArray(["not a key=1", ""]))
	assert_eq(c.get_int("k"), 2, "unlike the old format, pairs after text still count")


func test_section_comment_and_siblings() -> void:
	var c: FrogLordConfig = _parse("[A] # first\n[[A1]]\nx=1\n[B]\ny=2\n")
	assert_eq(c.children.size(), 2)
	assert_eq(c.get_child("A").comment, "first")
	assert_eq(c.get_child("A").get_child("A1").get_int("x"), 1)
	assert_eq(c.get_child("B").get_int("y"), 2)


func test_duplicate_key_is_an_error() -> void:
	var parser := ModernConfigParser.new()
	assert_null(parser.parse("k=1\nk=2\n", "root"))
	assert_string_contains(parser.error, "already set")


func test_too_deep_section_is_an_error() -> void:
	var parser := ModernConfigParser.new()
	assert_null(parser.parse("[[Deep]]\n", "root"))
	assert_string_contains(parser.error, "nested too deeply")


func test_unterminated_section_is_an_error() -> void:
	var parser := ModernConfigParser.new()
	assert_null(parser.parse("[Open\n", "root"))
	assert_string_contains(parser.error, "invalid section header")
