# Tower Game

A vertical tower-building simulation: place offices, homes, shops and elevators, keep tenants
happy, and grow the tower floor by floor. Built with Godot 4 and statically typed GDScript.
It is early work: the repo currently holds the project skeleton and workflow tooling.

## Homage notice

Tower Game is an original fan homage inspired by SimTower (1994). It is not affiliated with or
endorsed by the owners of that game. No original code, art, sound or text is used.

## Run and test

- Install Godot 4.7.2 and Python 3.12 or newer. Open `project.godot` in Godot and press F5.
- `python tools/setup.py` activates the git hooks on a fresh clone.
- Headless game tests: `godot --headless --path . --script res://tests/run_tests.gd`
- Python tool tests: `python -m unittest discover -s tools/tests`
- Everything, as CI runs it: `python tools/check.py --full`

## Docs

- [Roadmap](docs/roadmap.md) and [plan](docs/plan.md): what is being built, and when.
- [Gameplay reference](docs/gameplay-reference.md): the rules the game follows.
- [Workflow](docs/workflow.md), [efficiency](docs/efficiency.md) and [hooks](docs/hooks.md):
  how work is done here.
