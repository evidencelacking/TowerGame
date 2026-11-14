# Tower Game

A vertical tower-building simulation: an original homage to SimTower (1994), built with
Godot 4 and GDScript. It copies the genre's design, never the original's work.

## Values

Weigh every decision against these:

- **Efficiency:** fewer tokens and less rework. Enforce in code, not prose.
- **Review:** the owner decides what is ready and what is done.
- **Accuracy:** verified facts and tested behaviour only.
- **Creativity:** bring ideas, and propose bolder options when they serve the game.
- **Fun:** the point of the game. If it works but isn't fun, it isn't finished.

## Rules

- **Verify before asking or asserting.** Check the code, tools or docs first. Say what was
  actually tested, and label anything unverified.
- All work runs through issues: [docs/workflow.md](docs/workflow.md). Use `tools/issue.py`
  rather than raw `gh`. Reference issues with `refs #N`, never closing keywords.
- If the owner corrects the same thing twice, add a hook: [docs/hooks.md](docs/hooks.md).
- If an error repeats three times, stop and escalate rather than trying a fourth fix.
- Spend tokens by [docs/efficiency.md](docs/efficiency.md): Opus coordinates, Sonnet builds and merges.
- Gameplay questions go to the `gameplay-expert` agent, which reads
  [docs/gameplay-reference.md](docs/gameplay-reference.md). Check changes with `rules-keeper`.

## Clean room (the repo is public)

- No original code, art, sound, text, icons or data, and no decompiled or ported code of it.
- `references/` holds copyrighted manuals on the owner's machine. It is git-ignored: never
  read it except through `gameplay-expert`, and never copy from it into the repo.
- `python tools/check.py` fails on tracked reference files, PDFs, help files and executables.

## Code

- GDScript only, statically typed. Targets Windows first, full screen at modern resolutions.
- `scripts/sim/` is deterministic: integers only, no floats, no `randf`/`randi`, no `Time` or
  OS clock, a seeded RNG, and a fixed tick. Rendering reads from it; input reaches it only as
  commands. `tools/sim_lint.py` enforces this.
- Check licenses before reusing any code or art from elsewhere.

## Commands

- `python tools/setup.py` activates git hooks on a fresh clone and imports the project.
- `python tools/play.py` launches the game full screen (works from PowerShell). It imports first when
  the class cache is missing or older than any `.gd` file; tests and hooks do the same.
- Commit runs the relevant tests, and push and CI run them all. Godot itself: open `project.godot`, F5.
- Roadmap: [docs/roadmap.md](docs/roadmap.md). Plan: [docs/plan.md](docs/plan.md).
