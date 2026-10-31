class_name ThemeBookReader
extends RefCounted
## Reads the theme book ([ThemeBook]) and every theme's form library from the executable.
##
## Forms are named, and their entity types named, from FrogLord's lists
## ([GameNameLists]); a theme's form count is the number of names the list
## gives it.


## Reads the theme book of [param exe] and every form library, naming forms
## and entity types from [param names].
static func read(exe: ExeImage, names: GameNameLists) -> ThemeBook:
	var book := ThemeBook.new()
	if exe.version.theme_book <= 0:
		book.error = "this build has no theme book address"
		return book
	var reader: ByteReader = exe.reader_at(exe.version.theme_book)
	for theme: int in FroggerIds.THEMES.size():
		book.entries.append(ThemeBookRowReader.read_entry(reader, theme))
	if reader.has_error():
		book.error = "theme book: %s" % reader.error
		return book
	_read_forms(book, exe, names)
	return book


static func _read_forms(book: ThemeBook, exe: ExeImage, names: GameNameLists) -> void:
	var order: Array[int] = []
	var last: int = 0
	for theme: int in range(1, book.entries.size()):
		var current: ThemeBookEntry = book.entries[theme]
		var previous: ThemeBookEntry = book.entries[last]
		if current.form_library_pointer == 0 or previous.form_library_pointer == 0:
			continue
		var computed: int = (current.form_library_pointer - previous.form_library_pointer) / FormBookEntry.SIZE
		var named: int = _name_count(names, last)
		if computed != named:
			book.warnings.append("%s has %d form names but %d forms before the next library" % [
				FroggerIds.theme_name(last), named, computed])
		order.append(last)
		last = theme
	if book.entries[last].form_library_pointer != 0:
		order.append(last)
	for theme: int in order:
		var entry: ThemeBookEntry = book.entries[theme]
		var reader: ByteReader = exe.reader_at_pointer(entry.form_library_pointer)
		for local: int in _name_count(names, theme):
			var form: FormBookEntry = ThemeBookRowReader.read_form(reader, theme, local, book.all_forms.size())
			form.form_name = names.forms.name_of(form.global_id) if names.forms.has_name(form.global_id) else ""
			form.entity_name = names.entity_name_for(form.form_name, form.entity_type)
			entry.forms.append(form)
			book.all_forms.append(form)
		if reader.has_error():
			book.error = "%s form library: %s" % [FroggerIds.theme_name(theme), reader.error]
			return


static func _name_count(names: GameNameLists, theme: int) -> int:
	var bank: NameBank = names.forms.get_sub_bank(FroggerIds.theme_name(theme))
	return bank.size() if bank != null else 0
