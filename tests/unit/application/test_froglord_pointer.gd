extends GutTest
## The FrogLord pointer file round-trips its fields, reads as absent when
## missing and is replaced whole, leaving no temporary file.

const FOLDER: String = "user://froglord_test"
const PATH: String = FOLDER + "/current.cfg"


func before_each() -> void:
	_remove(FOLDER)


func after_all() -> void:
	_remove(FOLDER)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(child))
	for child: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


func _pointer(key: String, stamp: int) -> FrogLordPointer:
	var pointer := FrogLordPointer.new()
	pointer.index_root = "user://froglord/" + key
	pointer.fingerprint = key
	pointer.source_summary = "FrogLord mod modded_FROGGER.EXE + modded_FROGPSX.MWD over res://assets"
	pointer.report_path = pointer.index_root.path_join("support_report.tsv")
	pointer.written_at = stamp
	pointer.data_dir = "/FrogLord/save"
	pointer.fallback_root = "user://assets/fedcba9876543210"
	pointer.source_state = "modded_FROGGER.EXE:1762000000:4096"
	return pointer


func test_an_absent_pointer_reads_empty() -> void:
	var pointer: FrogLordPointer = FrogLordPointer.read(PATH)
	assert_false(pointer.exists())
	assert_eq(pointer.index_root, "")
	assert_eq(pointer.fingerprint, "")
	assert_eq(pointer.written_at, 0)
	assert_eq(FrogLordPointer.modified_time(PATH), 0)


func test_the_fields_round_trip() -> void:
	var written: FrogLordPointer = _pointer("0123456789abcdef", 1762000000)
	assert_eq(written.write(PATH), OK)
	var read: FrogLordPointer = FrogLordPointer.read(PATH)
	assert_true(read.exists())
	assert_eq(read.index_root, written.index_root)
	assert_eq(read.fingerprint, written.fingerprint)
	assert_eq(read.source_summary, written.source_summary)
	assert_eq(read.report_path, written.report_path)
	assert_eq(read.written_at, written.written_at)
	assert_eq(read.data_dir, written.data_dir)
	assert_eq(read.fallback_root, written.fallback_root)
	assert_eq(read.source_state, written.source_state)
	assert_false(FileAccess.file_exists(PATH + ".tmp"))


func test_a_rewrite_replaces_the_file_whole() -> void:
	assert_eq(_pointer("0123456789abcdef", 1762000000).write(PATH), OK)
	var first: int = FrogLordPointer.modified_time(PATH)
	assert_gt(first, 0)
	assert_eq(_pointer("fedcba9876543210", 1762000001).write(PATH), OK)
	assert_gte(FrogLordPointer.modified_time(PATH), first)
	var read: FrogLordPointer = FrogLordPointer.read(PATH)
	assert_eq(read.fingerprint, "fedcba9876543210")
	assert_eq(read.written_at, 1762000001)
	assert_false(FileAccess.file_exists(PATH + ".tmp"))
	assert_eq(DirAccess.get_files_at(FOLDER), PackedStringArray(["current.cfg"]))
