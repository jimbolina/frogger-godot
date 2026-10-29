---
name: plan-next-phase
description: Enter plan mode and produce a plan for the next roadmap phase of the Frogger Godot port, based on the repo's checkpoint, roadmap and code.
model: fable
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(git status:*), Bash(git log:*), Bash(git diff:*), EnterPlanMode, ExitPlanMode
---

Plan the next phase of work for this repository.

1. Call EnterPlanMode first. Make no edits until the plan is approved.
2. Read `AGENTS.md`, `docs/CURRENT.md` and `docs/PORTING.md`. Run `git status` and `git log -10` to see uncommitted work and what has landed.
3. Identify the next phase: the first incomplete item in the roadmap that CURRENT names as next, unless uncommitted changes show a phase already in progress. If it is ambiguous, say so and pick the most likely one.
4. Explore the code and docs that phase touches, using the domain index (`docs/reference/domain.md`), the architecture reference and the relevant golden specs under `tests/golden/specs/`.
5. Write the plan:
   - Goal and scope, and what is explicitly out of scope.
   - Files to add or change, with one responsibility per class and `src/source/` classes extending `RefCounted`.
   - Golden-test families needed, including independent Python generators and deliberate-break checks.
   - Work that can be delegated to sub-agents, with file ownership that does not overlap.
   - Verification: both retail and asset-free modes via `tools/run_tests.*`, strict compilation, and visual inspection where relevant.
   - Documentation to update (README, PORTING, CURRENT, references).
   - Risks, open questions and blockers.
6. Present the plan with ExitPlanMode.
