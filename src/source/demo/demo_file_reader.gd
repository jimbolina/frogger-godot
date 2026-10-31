class_name SourceDemoFileReader
extends RefCounted
## Decodes recorded PC demo resources into [SourceDemoFile]s.


## Reads three little-endian signed integers and the remaining input bytes.
static func parse(bytes: PackedByteArray, resource_name: String = "demo") -> SourceDemoFile:
	var demo := SourceDemoFile.new()
	if bytes.size() < 12:
		demo.error = "%s: demo header needs 12 bytes, found %d" % [resource_name, bytes.size()]
		return demo
	demo.duration = bytes.decode_s32(0)
	demo.start_grid_x = bytes.decode_s32(4)
	demo.start_grid_z = bytes.decode_s32(8)
	if demo.duration < 0 or demo.start_grid_x < 0 or demo.start_grid_z < 0:
		demo.error = "%s: negative demo duration or starting grid coordinate" % resource_name
		return demo
	demo.input_bytes = bytes.slice(12)
	return demo
