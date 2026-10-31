class_name RetailDirSource
extends GameDataSource
## An unmodified retail install: [code]FROGGER.EXE[/code] and [code]FROGPSX.MWD[/code] in one folder.

## Executable name in a retail install.
const EXE_NAME: String = "FROGGER.EXE"
## Archive name in a retail install.
const MWD_NAME: String = "FROGPSX.MWD"


## True if [param dir] holds both retail files.
static func looks_like(dir: String) -> bool:
	return not find_file_ignoring_case(dir, EXE_NAME).is_empty() \
		and not find_file_ignoring_case(dir, MWD_NAME).is_empty()


func kind_name() -> String:
	return "retail install"


func exe_file_name() -> String:
	return EXE_NAME


func mwd_file_name() -> String:
	return MWD_NAME


func get_exe_path() -> String:
	return find_file_ignoring_case(directory, EXE_NAME)


func get_mwd_path() -> String:
	return find_file_ignoring_case(directory, MWD_NAME)
