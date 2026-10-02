class_name ViewerCapture
extends RefCounted
## Common output rules for texture, model and map inspection captures.


## True for an absolute filesystem folder outside the source checkout after path normalization.
static func external_folder(folder: String) -> bool:
	if not folder.is_absolute_path() or folder.begins_with("res://") or folder.begins_with("user://"):
		return false
	var project: String = ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var resolved: String = folder.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var frozen: String = ProjectSettings.globalize_path("res://../froggy").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	return resolved != project and not resolved.begins_with(project + "/") and resolved != frozen and not resolved.begins_with(frozen + "/")


## Creates a permitted destination. Returns an actionable error, or an empty string on success.
static func prepare_folder(folder: String) -> String:
	if not external_folder(folder):
		return "Capture folder '%s' must be an absolute filesystem path outside the repository" % folder
	var result: Error = DirAccess.make_dir_recursive_absolute(folder)
	if result != OK:
		return "Cannot create capture folder '%s': %s. Choose a writable folder outside the repository." % [folder, error_string(result)]
	return ""


## Saves a capture. Returns an actionable error, or an empty string on success.
static func save_image(image: Image, path: String) -> String:
	if image == null:
		return "Cannot capture '%s': the viewport returned no image" % path
	var result: Error = image.save_png(path)
	if result != OK:
		return "Cannot write capture '%s': %s. Check the destination folder and write permissions." % [path, error_string(result)]
	return ""
