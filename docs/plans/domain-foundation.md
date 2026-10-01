# Remaining domain foundation work

The pre-P7 foundation establishes vocabulary, ownership, viewer helpers and
local checks. Settled rules belong in [domain](../reference/domain.md),
[architecture](../reference/architecture.md) and [testing](../reference/testing.md);
delivery evidence belongs in [foundation validation](../validation/domain-foundation.md).
This plan holds only deferred work and does not change P7/P8 acceptance.

## P7: prove the gameplay boundary

- Settle the PC 25/30 Hz discrepancy from frozen C traces and retail evidence
  before implementing movement. Keep exact timing in the simulation contract.
- Implement one source-backed grid/hop rule and owned frog state. Feed typed
  tick commands into the same rule from an asset-free test, single-step debug
  driver and playable scene. Rendering consumes state without changing it.
- Cover a normal hop, blocked destination, landing and source-established
  in-flight input handling. Compare independently produced reference traces.
- Verify repeatability across repeated runs and render schedules. Supply RNG
  state when first needed and record source-backed update order.
- Measure focused/full test duration and reproduction steps against the
  foundation baseline. Make further extractions only for a real caller.

## P7/P8: explain behavior

- Extend inspection with pause, tick step, reset and feature-specific state or
  collision overlays as those features arrive. Rewind may replay from reset.
- Add a scenario command for synthetic fixtures or player levels, seed and
  tick-indexed inputs. Emit compact text traces, first differing tick/field and
  a reproduction command; expected facts remain independently generated.
- Add structured diagnostics as needed: code, severity, build/resource,
  entity/form or source offset, and fallback. Unknown names remain visible.
- Measure tick/load/conversion costs and resource counts. Keep captures outside
  the repository and avoid hard timing limits on uncalibrated shared runners.

## P8 and later

- Apply definition/state/view ownership to paths, entities and scripts. Resolve
  types/forms/callbacks through verified names and supported implementations;
  preserve source ordering and test unknown mappings. Mods never load new code.
- Prove that another original behavior needs only its own tests and a narrow
  registry/adapter change. Reassess after the first playable level.
- Add progression/save/reload boundaries only in their owning phases.
- When a repository host is selected, add asset-free CI pinned to Godot 4.5.1,
  starting with one verified desktop runner. Retain logs, enforce allowed skips
  and keep legally held retail data in local/private gates.

Distill completed work into references and validation, remove it here, and
delete this plan when no deferred scope remains. P7 timing and per-build form
callback address mappings remain unresolved source investigations.
