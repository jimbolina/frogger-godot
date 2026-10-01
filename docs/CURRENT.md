# Current checkpoint

Updated: 2026-10-01. Replace this checkpoint; do not append a journal.

**P6 complete: map parsing, rendering and inspection cameras.**
The orchestrator integrated `gpt-6.1-sol` agents for readers, rendering,
viewer/cameras and independent Python/C facts. See the
[map contracts](reference/maps.md) and
[validation report](validation/p6.md).

**Next action:** plan P7 against the roadmap, current implementation and
frozen C per-tick traces: grid, frog movement, gameplay camera, collision
and deaths. Settle the timing contract before implementing movement.

Final serial checks: 131 scripts compile strictly; retail 297 passed with
zero skips; asset-free 246 passed with 51 named retail skips (exit 3).
All 78 high/low map loads and resource-release switches passed. Seven new
fact tables passed deliberate-break/restoration checks. All eleven selected
reference scenes pass the unchanged numeric thresholds. SUB1 repeat captures
are identical; measured load and playback budgets pass without render-resource
growth. Evidence and external capture locations are in the report.

The owner's FrogLord-saved JUN1 low-detail map loads with an identical
standalone/embedded index. Same-pose captures confirm raised terrain;
independent records confirm four removed tree entities. Automatic entity
placement/rendering remains P8, so tree models are absent from both views.
The final wrappers passed after this compatibility check.

Never push. The licence remains the owner's decision before publication.
