# Current checkpoint

Updated: 2026-10-01. Replace this file when work changes; never append a journal.

**Next work: plan P6 — map parsing, rendering and camera.**
The [P6 planning brief](plans/p6-maps.md) contains the survey checklist and
existing scope. Begin by inventorying retail map formats and tracing
FrogLord's map reader/writer plus the frozen C camera/rendering code.
No P6 implementation has started or detailed plan been approved.

P5 is complete in `957b9a0`; model animation, flipbooks and animated textures
are available. Maps remain the next phase. The documentation reorganization
changes no runtime code or golden facts.

**Pending input:** an owner-supplied FrogLord-saved folder with all three
`modded_*` files is needed for the P6 compatibility gate, but does not block
survey/planning. The project licence is an owner decision before publication.

**Latest verification, rerun after documentation reorganization:** 99 scripts compiled; 240 retail tests passed;
198 asset-free tests passed with 42 named retail skips. Full P5 visual,
reference and timing evidence is in [its validation report](validation/p5.md).
Use Git for working-tree and commit state; no separate uncommitted handoff
or external implementation work is pending.
