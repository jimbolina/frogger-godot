# Golden data

These are text facts only: names, sizes, flags, counts, IDs and digests.
Never commit retail bytes or excerpts. Tests load the owner's retail files
through `FROGGER_DATA_DIR` and compare decoded values with these facts.

Generators in `tools/` independently implement FrogLord's formats and the
C reference's playback calculations in Python. They share no GDScript
implementation. Never regenerate expected results from Godot output.
Every new family requires a deliberate-break check: corrupt one fact,
observe the intended failure, then restore it.

## Specifications and reproduction

Read only the specification for the format being changed. Each lists the
files, columns, generator command, and independent cross-checks. All
commands run from the repository root; generated facts live in
`pc-retail-v3.0e/` or `synthetic/`, as specified for each family.

| Format | Specification |
|---|---|
| MWI, MWD, WAD, PowerPacker | [Archives](specs/archives.md) |
| Executable tables | [Executable tables](specs/executable-tables.md) |
| VLO images | [Textures](specs/textures.md) |
| Static models and stored MOF facts | [Models](specs/models.md) |
| XAR, flipbooks and animated textures | [Animation](specs/animation.md) |
| Maps, animation counters, cave falloff, projection and SkyLand | [Maps](specs/maps.md) |
| Final-PC PATH records and source path updates | [Paths](specs/paths.md) |
| Final-PC entity identities, FORM grids, transforms, contacts, bounded POP/SAFE, guarded JUN1 zones/route, ORG1 script/route proof and visibility lifecycle | [Entities](specs/entities.md) |
| Synthetic grid surface and layer queries | [Grid queries](specs/grid.md) |
| Synthetic frog controller/mover, collision and terrain callback records | [Terrain components](specs/terrain-components.md) |
| Synthetic default camera component records | [Default camera](specs/camera-components.md) |
| Synthetic gameplay projection and source-rendered geometry | [Gameplay projection](specs/gameplay-projection.md) |
| Synthetic frog animation catalog and component records | [Frog animation](specs/frog-animation.md) |
| Synthetic ordered terrain/camera/animation component records | [Integrated terrain](specs/integrated-terrain.md) |

## Digest convention

A **list digest** is the SHA-256 of the list's decimal values joined by
commas, with no spaces: `sha256(",".join(str(v) for v in values))`. Both the
generator and the Godot tests compute it from decoded values, never from raw
bytes.

Format-specific geometry/pixel ordering, padding and hash algorithms are
specified in the linked documents. Do not assume every digest hashes raw bytes.
