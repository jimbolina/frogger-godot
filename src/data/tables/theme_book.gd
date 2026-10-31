class_name ThemeBook
extends Resource
## The theme book: one [ThemeBookEntry] per theme, with each theme's forms.
##
## There is always one row per theme number (11). A theme's form library
## stores no length; as in FrogLord, the number of forms read is the number
## of names FrogLord's form list gives that theme. The distance to the next
## theme's library (32 bytes per form) must agree, and a disagreement is
## recorded in [member warnings] rather than trusted over the names.

## Rows in theme-number order.
@export var entries: Array[ThemeBookEntry] = []
## Every form of every theme, in theme order (index = [member FormBookEntry.global_id]).
@export var all_forms: Array[FormBookEntry] = []
## Non-fatal disagreements found while reading.
@export var warnings: PackedStringArray = PackedStringArray()
## Why reading failed, or "".
@export var error: String = ""


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
