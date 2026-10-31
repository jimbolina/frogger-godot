# Executable tables

Retail counts below refer to `pc-retail-v3.0e`. See [source locations](../../../docs/reference/sources.md).

| Table | Count |
|---|---|
| Map book rows | 60, of which 39 have a map |
| Themes | 11; one is empty |
| Forms | 368 across 10 themes |
| Texture remaps | 79, holding 3,811 ids |
| Texture pointers | 1,858 |
| Scripts | 125, with 647 commands |
| Script opcodes | 49 |
| Music entries | 60 |
| Demos | 34 rows in each of two lists |
| Level select | 33 arcade, 5 race |
| Pickups | 19 |

- **Table lengths are not stored.** The map book runs up to the theme book's address. Theme book and pickup sizes come from FrogLord's lists of themes and pickups. The script table's length is the number of names in the script name list, so name lists load before tables.
- **Addresses in the version files are file offsets. Pointers inside tables are memory addresses**; subtract `ramOffset` to get a file offset.
- **The demo table's address is in no version file.** FrogLord searches the executable for it. A FrogLord-saved executable records the address in its appended block.
- **There are two demo lists.** The first is for low-poly levels, the second for high-poly. This project uses the second.
- When reading a FrogLord-saved executable, table reads stay inside the original executable length.
- An unknown music track number is kept as read, so edited executables load.

## Format differences

Follow FrogLord for these format rules; they agree on retail values.

| Subject | FrogLord | Reference engine |
|---|---|---|
| End of the last remap | Stops at a zero | Uses the map's highest texture index plus one |
| Size of the sky-land remap | 76 ids | 154 bytes, counting the terminator |
| Map book rows 4 and 57, which have remap pointers but no map | Skipped | Used as boundaries |

## Behavior mapping

`EntityScriptSetup` resolves the bounded supplied script closure and opcode
callbacks through FrogLord names. Unknown names or unsupported instructions
reject execution; general inspection can still display their decoded facts.
The [entity contract](../../../docs/reference/gameplay/entities.md#supported-script-components) owns
the implemented subset and turtle creation's named script replacement.
The guarded ORG1 corridor pins both the numeric program facts and named
entity/form/script/callback bindings; changed names cannot silently reinterpret
an otherwise identical instruction stream.

Form callbacks retain executable addresses as source facts. Before implementing
their behaviors, verify address-to-name mappings for each supported build; setup
then selects a supported implementation by that name, never executes an address.
FrogLord's script `CallbackNames` sub-bank names opcode callbacks and does not
establish these form callback address mappings. Unknown mappings need visible
diagnostics and a behavior-specific safe fallback before behavior execution. See the
[domain trace](../../../docs/reference/domain.md#following-a-form).

## Recorded demo resources

`SourceDemoFile` decodes the resource selected by the supplied executable's demo
row. High detail selects `demo_resource_id`; low detail selects the matching
low-poly id. No retail resource number is built into playback.

The resource starts with three little-endian signed 32-bit integers: duration,
starting grid X and starting grid Z. Short headers and negative values report the
resource identity. All remaining unsigned input bytes are preserved, including
unused capacity. Cursor reads outside this buffer return exhaustion explicitly.
Duration counts elapsed demo ticks; it does not specify how many input records
will be consumed. Playback owns those two counters separately.

FrogLord's `FroggerDemoFile` editor reads at most 1800 bytes and writes a fixed
1800-byte array. Its own format note says the original game can read larger
buffers. This reader preserves all supplied bytes, allowing extended player
recordings while enforcing bounds during playback. Bit 2 remains uninterpreted;
raw bits are never normalized by decoding. See the [demo golden specification](../../../tests/golden/specs/demos.md).

## Sound metadata

For `pc-retail-v3.0e`, sound initialization at `0x42358B` passes sample table
`0x46F938`, group table `0x46F920`, and bank table `0x46F890` to `0x44BDC0`.
`SoundTables` reads twelve bank resource pairs, four voice groups, and 174 sample
records. PC sample records are 32 bytes: the frozen C sample fields occupy the
first 24 bytes and two additional runtime pointers occupy the final eight.
Supplied sample flags, bank/group assignments, notes and pitch-modulation values
remain authoritative. The sixty checkpoint/completion pitch pairs at `0x470F20`
are signed 32-bit values; application setup resolves their semitone offsets.

The retail sample fields match frozen `sound.c` except sound 142, whose supplied
flag is LOOPED while frozen C says REPEAT. Preserve the supplied flag. The
independent [sound facts](../../../tests/golden/specs/sound.md) verify every row,
the initialization code identity and bank sample lengths. Unknown groups,
unsupported flags and missing selected-bank samples retain explicit diagnostics.
