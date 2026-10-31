class_name ExePointer
extends RefCounted
## Tests on values read from a Windows program image.


## True if [param value] looks like an address inside a Windows program
## (0x004xxxxx), the test FrogLord uses to find where pointer lists end.
static func looks_like(value: int) -> bool:
	return (value & 0xFFF00000) == 0x00400000
