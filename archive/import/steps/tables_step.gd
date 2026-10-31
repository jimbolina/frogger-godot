extends ImportStep
## Saves the executable's decoded tables: one resource per table under
## [code]tables/[/code] and [code]tables/game_tables.tres[/code] linking them.
##
## Each table is saved first, so [GameTables] refers to it as an external
## resource and every table can be opened and edited on its own. The pickup
## table is a plain array and stays inside [code]game_tables.tres[/code].


## Table file names by [GameTables] property, in save order.
const TABLES: Dictionary[String, String] = {
	"map_book_table": "map_book",
	"theme_book_table": "theme_book",
	"bmp_pointer_table": "bmp_pointers",
	"remap_table": "remaps",
	"script_table": "scripts",
	"score_table": "scores",
	"high_score_table": "high_scores",
	"music_table": "music",
	"level_select_table": "level_select",
	"demo_list": "demo_table",
	"sound_table": "sound_tables",
	"particle_generator_table": "particle_generators",
	"splash_list_table": "splash_lists",
}


func step_name() -> String:
	return "tables"


func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_RESOURCES])


func run(context: ImportContext, phase: String) -> void:
	if phase != PHASE_RESOURCES:
		return
	var tables: GameTables = context.data.tables
	if tables == null:
		context.report("tables: the executable's tables were not read")
		return
	for problem: String in tables.errors():
		context.report("tables: %s" % problem)
	for property: String in TABLES:
		var table: Resource = tables.get(property)
		if table == null:
			context.report("tables: %s was not read" % TABLES[property])
			continue
		table.resource_name = TABLES[property]
		ImportContext.number_sub_resources(table)
		context.save_resource(table, context.table_path(TABLES[property]))
	tables.resource_name = "%s tables" % context.data.version.internal_name
	ImportContext.number_sub_resources(tables)
	context.save_resource(tables, context.table_path("game_tables"))
