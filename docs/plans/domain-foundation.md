# Remaining domain foundation work

Settled vocabulary, ownership and local checks belong in
[domain](../reference/domain.md), [architecture](../reference/architecture.md)
and [testing](../reference/testing.md). Delivery evidence belongs in
[foundation validation](../validation/domain-foundation.md) and
[P7 validation](../validation/p7.md). This plan holds deferred scope only.

## P8 and later

- Apply definition/state/view ownership to paths, entities and scripts. Resolve
  types/forms/callbacks through verified names and supported implementations;
  preserve source ordering and test unknown mappings. Mods never load new code.
- Add structured entity diagnostics as needed: code, severity, build/resource,
  entity/form or source offset, and fallback. Unknown names remain visible.
  Per-build form callback address mappings require source investigation.
- Prove that another original behavior needs only its own tests and a narrow
  registry/adapter change. Reassess after the first playable level.
- Extend feature-specific inspection and scenario commands with entity/path
  state as those features arrive. Rewind may replay from reset.
- Measure tick/load/conversion costs and resource counts. Keep captures outside
  the repository and avoid hard limits on uncalibrated shared runners.
- Add progression/save/reload boundaries only in their owning phases.
- When a repository host is selected, add asset-free CI pinned to Godot 4.5.1,
  starting with one verified desktop runner. Retain logs, enforce allowed skips
  and keep legally held retail data in local/private gates.

Distill completed work into references and validation, remove it here, and
delete this plan when no deferred scope remains.
