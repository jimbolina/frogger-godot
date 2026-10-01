# Architecture and ownership

## Dependencies

- `src/legacy/` decodes source facts, with file I/O where needed. Classes derive
  from `RefCounted` and depend on neither Nodes/tree access nor conversion,
  gameplay, scenes or presentation.
- Future `src/game/` contains `RefCounted` definitions, live state and rules.
  It receives validated definitions and tick commands from setup adapters;
  it does not depend on legacy readers, conversion or presentation, open files,
  poll input, consult wall time or access Nodes. Godot math types are allowed.
- Setup adapters belong with their first real consumer. They resolve source
  names and supply concrete dependencies; no container or global world is needed.
- Conversion builds render resources from decoded data. Presentation owns
  scene lifetimes, input translation and drawing. `MapSceneData` is a rendering
  dependency bundle, not the future world's authoritative state.
- Future simulation uses direct calls for ordered updates. Notifications follow
  state changes; subscriber order must not decide collision outcomes or RNG use.
  Rendering interpolation cannot feed back into authoritative state.

The [domain glossary](domain.md) gives semantic boundaries. Existing
[simulation](simulation.md), [coordinates](coordinates.md) and topic references
remain authoritative for detailed rules.

## Current lifetimes

`GameData` owns its archive, decoded executable tables and caches. Treat shared
decoded objects as read-only after construction. Closing it closes its archive;
retained decoded records do not make later archive reads valid.

Viewer `open_data(game_data, take_ownership = false)` borrows by default. The
caller must keep borrowed data open until every consumer has detached. A viewer
that opens its own data passes `true`, closes it when replaced or exiting, and
releases its drawing resources. Reattaching the same object never closes it or
silently relinquishes ownership. Do not transfer ownership to multiple viewers.

Meshes/materials belong to their rendering bundle or instance according to the
existing conversion APIs. Instance animation clocks are separate from shared
model definitions. Source replacement clears selections, caches and drawing
references before another source is shown. Standalone viewer entry points and
synthetic injection remain supported.

Future runs will own frog/entity clocks, commands, RNG and mutable state; their
coordinator will make source-backed update order explicit. P7/P8 must establish
these concrete owners when the state is implemented, not add unused scaffolding.

## Extending behavior

1. Find the source rule under the [source policy](sources.md).
2. Name its inputs, owned state, units and observable outcomes.
3. Add an asset-free example to the owning feature's unit tests.
4. Connect the setup adapter and named supported implementation.
5. Compare independent reference facts/traces and expose actionable diagnostics.

Implementing another original behavior is a code change. A mod only repoints
data to already supported behavior. Keep raw identifiers for diagnostics;
never dispatch executable addresses directly.

## Automated checks

Both test wrappers compile scripts, check architecture, then run tests and
validate their results; see [testing](testing.md). The architecture scanner
checks protected code and its statically discoverable dependencies, including
project class names, literal script paths and inherited bases. It reports
computed loads and dynamic calls for review. Gameplay runtime resource loading
is file I/O; literal preloads of permitted script definitions are allowed.

This is a conservative static check, not a complete GDScript parser or proof of
runtime purity. It does not resolve local type scopes, inner-class aliases or
dependencies embedded in serialized resources. Identifier shadowing and reflective
code require human review; comments and unrelated strings are excluded. Ordinary
data methods such as `FrogLordConfig.add_child()` are allowed. Keep dependencies
explicit instead of obscuring them to pass the check. Hosted CI remains deferred.
