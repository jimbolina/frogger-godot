extends ImportStep
## Saves every recorded demo (each MWI entry named [code]*.DAT[/code]) as a
## [SourceDemoFile] at [method ImportContext.demo_path].


func step_name() -> String:
	return "demos"


func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_RESOURCES])


func run(context: ImportContext, phase: String) -> void:
	if phase != PHASE_RESOURCES:
		return
	for entry: MwiEntry in context.data.mwi.entries:
		var file_name: String = entry.display_name()
		if not file_name.to_upper().ends_with(".DAT"):
			continue
		var problems := PackedStringArray()
		var bytes: PackedByteArray = context.data.read_resource(entry.index, problems)
		if bytes.is_empty():
			context.report("demo %s: %s" % [file_name, "; ".join(problems)])
			continue
		var demo: SourceDemoFile = SourceDemoFile.parse(bytes, file_name)
		if not demo.is_valid():
			context.report("demo %s: %s" % [file_name, demo.error])
			continue
		demo.resource_name = file_name
		context.save_resource(demo, context.demo_path(context.entry_name(entry.index)))
