extends RetailTest
## Needs the retail files: the texture viewer lists every texture bank and
## shows a chosen one with the image count the golden facts record.

const VIEWER_SCENE: String = "res://scenes/tools/texture_viewer.tscn"


func test_viewer_loads_banks_by_name() -> void:
	var scene: PackedScene = load(VIEWER_SCENE)
	var viewer: TextureViewer = scene.instantiate()
	viewer.auto_open = false
	add_child_autofree(viewer)
	viewer.open_data(GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e")), true)
	var golden: Dictionary[String, int] = {}
	for row: PackedStringArray in GoldenFiles.rows("vlo_files.tsv"):
		golden[row[1]] = row[3].to_int()
	assert_eq(viewer.bank_names().size(), golden.size())
	for bank_name: String in ["SUB_VRAM.VLO", "LS_ALL.VLO", "OPTE_RAM.VLO"]:
		var count: int = viewer.load_vlo_by_name(bank_name)
		assert_eq(count, golden[bank_name], bank_name)
		assert_eq(viewer.cell_count(), count)
	assert_eq(viewer.load_vlo_by_name("NO_SUCH.VLO"), -1)
