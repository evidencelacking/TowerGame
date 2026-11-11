# Roadmap

A direction, not a contract. Draft for the owner's review, 2026-11-10.
Task detail: [plan.md](plan.md). Rules of the original: [gameplay-reference.md](gameplay-reference.md).

## The target

**A vertical tower-building simulation, an homage to SimTower (1994).** It first reproduces
that game's rules and play loop closely, runs full screen at modern resolutions on current
systems, and then becomes our own.

## What "homage" means

- **We copy the design, not the work.** Genre mechanics are ours to use: a cut-away tower,
  rooms on a grid, tenants with schedules, elevators, stress, grades and stars.
- **Everything players see or hear is original:** name, art, sound, music, text, icons,
  event wording and UI look.
- **No code or data from any port or decompilation of the original.** The repo is public and
  written clean-room from described behaviour. Builders never read such code.
- **Reference material stays local** in `D:\Claude\Tower Game\references\` (git-ignored):
  the manual and four player guides. The repo cites them and never copies their text.
- **Faithful first, then better.** Where the original had a bug (the double-funds trick,
  the B10 trap), we leave it out. Where it had a pain point (rent changed one room at a
  time), we fix it once the baseline plays right.

## Key decisions (proposed, owner to confirm)

| Decision | Proposal | Why |
|---|---|---|
| Engine | Godot 4, GDScript, statically typed | Same as the strategy game: its skill, hooks, lint and CI carry over. Full screen, scaling and Windows/Mac/Linux export built in |
| Simulation | `scripts/sim/`: integers only, fixed tick, seeded random, commands in | Deterministic, testable headless, replayable; saves are just state |
| Display | Native Godot shapes (coloured blocks, simple people) until the game plays well; original pixel art at integer scale in M10 | Playable before art (owner, 2026-11-10). No art from the original |
| Platforms | Windows first; Mac and Linux checked at milestones | The owner's machine |
| Repo | `evidencelacking/TowerGame` (public, empty) | Owner's choice; strict content boundary |
| Values in conflict | Manual wins unless the player guides agree with each other; else we tune | Owner, 2026-11-10 |
| Name | "Tower Game" until the art direction (M10) | |

## Who decides what

- **The owner** approves issues, closes work and plays at milestones.
- **The `gameplay-expert` agent** checks every gameplay issue against the original before it
  goes to the owner, and answers rules questions during building.
- **Opus coordinates, Sonnet builds,** Haiku searches, as in the strategy game.

## The path

| | Milestone | Done when | Owner plays |
|---|---|---|---|
| M0 | Repo and workflow | A builder takes an issue to a merged PR with hooks and CI | No |
| M1 | Engine skeleton | Full-screen window, camera, grid, clock running | Look and feel |
| M2 | Build a tower | Lobby, floors, offices, condos, stairs, bulldoze, money | Yes |
| M3 | People and stairs | Workers commute by stairs and feel stress | Yes |
| M4 | Elevators | Local elevators carry people; waiting causes stress | Yes |
| M5 | Economy and grades | Rent, quarters, A/B/C, tenants come and go, save/load | Yes: **1 to 2 stars** |
| M6 | Hotel and commerce | Hotels, food, shops, cleaning, pests, daily income | Yes |
| M7 | Stars and services | Star rules; security, medical, recycling, parking | Yes: **2 to 3 stars** |
| M8 | Big-tower transport | Sky lobbies, express, service, escalators, elevator panel | Yes: **3 to 4 stars** |
| M9 | Events | Fire, threat, VIP, treasure, rain, seasonal fly-past | Yes |
| M10 | Look, sound and UI | Original art, name, sound, overview map, quality-of-life tools | Yes |
| M11 | Full game | Theatre, party hall, metro, cathedral, wedding, tutorial, release build | **Full run to the top rank** |
| M12+ | Make it our own | Owner-picked changes from the ideas list | Per change |

The order follows the original's own climb: each milestone unlocks the next star, so every
owner playtest is a real stretch of the game.

## Make it our own (ideas after M11)

Our own cheats, wider and taller towers, several towers on one lot, modern rooms (gym, co-working, rooftop
garden, data centre), smarter elevator AI to tune, weather and seasons, tenant stories,
scenarios with goals, a fix for the lowest-rent exploit, mod-friendly room data,
accessibility, controller and touch input.

## Open questions for the owner

1. Godot 4 and GDScript, as in the strategy game?
2. When `TowerGame` is set up (task 0.1), these docs move there. Agreed?
3. Name now, or with the art direction in M10?
Settled 2026-11-10: conflicting values (rule above), elevators (local 17, express 36),
our own cheats later, and native shapes before art.
