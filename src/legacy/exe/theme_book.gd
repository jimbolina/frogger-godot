class_name ThemeBook
extends RefCounted
## The theme book: one [ThemeBookEntry] per theme, with each theme's forms.
##
## There is always one row per theme number (11). A theme's form library
## stores no length; as in FrogLord, the number of forms read is the number
## of names FrogLord's form list gives that theme. The distance to the next
## theme's library (32 bytes per form) must agree, and a disagreement is
## recorded in [member warnings] rather than trusted over the names.

## Rows in theme-number order.
var entries: Array[ThemeBookEntry] = []
## Every form of every theme, in theme order (index = [member FormBookEntry.global_id]).
var all_forms: Array[FormBookEntry] = []
## Non-fatal disagreements found while reading.
var warnings: PackedStringArray = PackedStringArray()
## Why reading failed, or "".
var error: String = ""


## Reads the theme book of [param exe] and every form library, naming forms
## and entity types from [param names].
static func read(exe: ExeImage, names: GameNameLists) -> ThemeBook:
	var book := ThemeBook.new()
	if exe.version.theme_book <= 0:
		book.error = "this build has no theme book address"
		return book
	var reader: ByteReader = exe.reader_at(exe.version.theme_book)
	for theme: int in FroggerIds.THEMES.size():
		book.entries.append(ThemeBookEntry.read(reader, theme))
	if reader.has_error():
		book.error = "theme book: %s" % reader.error
		return book
	book._read_forms(exe, names)
	return book


## The row of theme [param theme], or null.
func get_entry(theme: int) -> ThemeBookEntry:
	return entries[theme] if theme >= 0 and theme < entries.size() else null


## The form a map in theme [param theme] means by [param form_book_id]: bit 15
## selects GENERAL, the low bits are the position in that theme's library.
## Returns null when there is no such form.
func get_form(theme: int, form_book_id: int) -> FormBookEntry:
	var owner: int = FroggerIds.THEME_GENERAL if form_book_id & FormBookEntry.GENERAL_BIT != 0 else theme
	var entry: ThemeBookEntry = get_entry(owner)
	var index: int = form_book_id & (FormBookEntry.GENERAL_BIT - 1)
	if entry == null or index >= entry.forms.size():
		return null
	return entry.forms[index]


## Number of forms in all themes.
func form_count() -> int:
	return all_forms.size()


func _read_forms(exe: ExeImage, names: GameNameLists) -> void:
	var order: Array[int] = []
	var last: int = 0
	for theme: int in range(1, entries.size()):
		var current: ThemeBookEntry = entries[theme]
		var previous: ThemeBookEntry = entries[last]
		if current.form_library_pointer == 0 or previous.form_library_pointer == 0:
			continue
		var computed: int = (current.form_library_pointer - previous.form_library_pointer) / FormBookEntry.SIZE
		var named: int = _name_count(names, last)
		if computed != named:
			warnings.append("%s has %d form names but %d forms before the next library" % [
				FroggerIds.theme_name(last), named, computed])
		order.append(last)
		last = theme
	if entries[last].form_library_pointer != 0:
		order.append(last)
	for theme: int in order:
		var entry: ThemeBookEntry = entries[theme]
		var reader: ByteReader = exe.reader_at_pointer(entry.form_library_pointer)
		for local: int in _name_count(names, theme):
			var form: FormBookEntry = FormBookEntry.read(reader, theme, local, all_forms.size())
			form.form_name = names.forms.get_name(form.global_id) if names.forms.has_name(form.global_id) else ""
			form.entity_name = names.entity_name_for(form.form_name, form.entity_type)
			entry.forms.append(form)
			all_forms.append(form)
		if reader.has_error():
			error = "%s form library: %s" % [FroggerIds.theme_name(theme), reader.error]
			return


static func _name_count(names: GameNameLists, theme: int) -> int:
	var bank: NameBank = names.forms.get_sub_bank(FroggerIds.theme_name(theme))
	return bank.size() if bank != null else 0
