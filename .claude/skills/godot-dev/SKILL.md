---
name: godot-dev
description: Godot 4 rules for Tower Game. Use before writing or changing .gd, .tscn or .tres files, adding nodes, input, UI or rendering code, or claiming a game change works.
---

## Simulation or view?

Decide first. `scripts/sim/` must give identical results on every machine and every run.

| Need | Simulation | View |
|---|---|---|
| Timing | Tick counts | `_process`, `Timer`, `Tween` |
| Randomness | A seeded integer generator in the state | `randf()` for cosmetic effects only |
| Numbers | Integers (money in whole dollars, fixed-point where needed) | Floats |
| Movement | Integer positions on the grid | Interpolate between ticks |
| Reacting to events | Direct, ordered calls | Signals |

Input reaches the simulation only as queued commands applied at a tick, so never call the
tick function from input code. `python tools/sim_lint.py` enforces the banned list; it also runs
in the commit hook and in CI.

## GDScript

- Godot 4 syntax only: `await`, `signal.connect(callable)`, `instantiate()`, `@export`,
  `@onready`. Older tutorials use names that no longer exist.
- Statically type everything, including `for x: int in values` where it isn't inferred.
- Prefix private members with `_`, and use `##` for doc comments.
- Use `preload` for known paths. Use signals for view code, not for simulation order.
- Game data (rooms, costs, schedules) lives in data files or constant tables, not scattered
  through logic, so tests can check them against `docs/gameplay-reference.md`.

## Scenes

- `.tscn` files are text and safe to edit, but keep their `load_steps` and resource ids valid.
  Commit `.uid` files with their scripts.
- Name nodes for their job: `MoneyLabel`, not `Label2`.
- Put the HUD on a `CanvasLayer` so it ignores the camera. The window is resizable and runs full
  screen, so lay out HUD controls with anchors and containers, never fixed pixel positions.

## Proving it works

1. Commit and push: the hooks run the tests. Run one suite by hand only to answer a question
   (`docs/workflow.md`, When to test).
2. Run Godot scripts under `timeout N` with output in a file:
   `timeout 120 godot --headless --path . --script res://tests/run_tests.gd > out.txt`
3. Check anything visual by looking at a capture or running the game. Separate what was tested
   from what is assumed. Logs and scene trees don't prove visuals, timing or feel. If you
   couldn't check something, say so.
