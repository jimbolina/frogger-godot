# Animation and integrated component evidence

The animation generator independently extracts 35 frozen script catalog entries
and 34 named actions, checks compiled C tables, and compares 320 script/pose
records against its Python interpreter. The integrated generator independently
composes movement/collision, camera and animation for 1,464 six-phase records
with 42 fields. Both generators pass after linking the unchanged frozen objects.
The [animation boundary](../reference/frog-animation-control.md) and
[integrated corpus specification](../../tests/golden/specs/integrated-terrain.md)
define the represented state and omitted systems.

Two fresh process runs per adapter produced byte-identical stdout. SHA-256:

| Adapter | Stdout digest |
| --- | --- |
| Animation | `5dab71b5e25d771c28c8fbc372626ce191a845473a7cc5a75cb9f1861107133f` |
| Integrated terrain | `7253e7d34c40b414aac79702a31adc037c7ae1401160860368767a4654c4de18` |

Binary/link-input/source hashes and deterministic stdout evidence are retained
outside the repository under the session visualization directory, in
`animation-oracle` and `integrated-terrain-oracle`. No retail bytes or binaries
are included in these golden families.

The animation baseline focused wrapper passed strict compilation and architecture
checks for 181 scripts, then four tests with 10,079 assertions. Changing the
first script-phase expected action from 16 to 17 produced exactly one failed
assertion (scenario 0, tick 0, scripts) while strict compilation of 182 scripts
passed. The expected file was restored byte for byte. The restored animation
and integrated comparison wrapper passed strict compilation/architecture for
189 scripts, six tests and 61,079 assertions in 2.443 seconds of GUT execution.
The integrated test checks all represented fields at five public phases,
including shared random state, reset replay and detached camera/animation state.
Its independent scalar deliberate-break was included in the seventeen-family
probe: exactly seventeen failures, followed by byte-identical restoration and
40 passing tests with 159,582 assertions. See [P7 validation](p7.md) for the
manifest and restored wrapper logs.

Baseline logs: `frogger-tests-9397deb5b7b34bbe8ebe8bc60f93fe87`.
Deliberate-break logs: `frogger-tests-1a946a6f3f6b426b8580b7475a18550a`.
Restored/integrated logs: `frogger-tests-559e967ee2fa4eac8c573635749d5876`.
These focused checks are not the final retail/asset-free phase gates.
