# Art standard (draft)

Status: draft for #240. The owner picks one of three mock-ups; the winner's palette and rules
replace the "Palette" section below and feed the renderer (M10.2). All wording is ours.

## Feel rules

1. **Side-on cutaway.** The tower is a slice through a building. Each room is a lit box we look into.
2. **Readable grid.** Walls and floor slabs are dark and thin, so every room edge and floor line
   stays visible at any zoom. The grid is never lost behind decoration.
3. **One colour, one silhouette.** Each room kind has one dominant colour and one strong furniture
   shape (desk and monitor, bed, table and hanging lamp, counter). A room is identifiable at a glance.
4. **Light means use.** A room is bright when someone is in it or it is open, and dark when empty.
   The tower reads as alive from across the screen.
5. **The sky tells the time.** Sky colour, sun, moon and stars carry the time of day. Windows show
   the same sky.
6. **People are tiny but countable.** About 3x7 native px, one colour per type. Alone they are
   marks, together they read as a crowd in motion.
7. **Elevator cars are the main movers.** The car is the brightest moving shape in the shaft, and
   its occupants show.
8. **Every activity has a visual.** If the sim knows someone is doing something, the view shows it.

## Art rules

- Everything is drawn by code (`_draw()` and recipes). No image files in the game.
  (Documentation screenshots in `docs/mockups/` are not game assets.)
- Native resolution is low: 8 px per floor-unit column and 24 px per floor. Drawing happens in a
  SubViewport at that size and is shown nearest-filtered at a whole-number scale, never fractional.
- Original palettes only; nothing is sampled from the original game or any other source.
- Art reads simulation state only and adds no saved state.

## Mock-ups

Scenes in `res://mockups/` (not the main scene), one floor slice each: lobby, office,
hotel, food, stairs, one shaft with a car, and people. Day on top, night below.

| Direction | Scene | Look |
|---|---|---|
| A | `art_a.tscn` | Warm, saturated, chunky dark outlines on furniture. |
| B | `art_b.tscn` | Muted, thin line furniture, cool dusk-and-night palette. |
| C | `art_c.tscn` | Flat bold colour, black walls, white and black figures, high contrast. |

Launch (PowerShell): `python D:\Claude\TowerGame\tools\play.py --scene res://mockups/art_a.tscn`.
Captures: `docs/mockups/art_<x>_day.png` and `_night.png`, made by running a scene windowed with
`-- --capture=<dir>`. Headless Godot has no renderer, so capture needs a window.

## Palette

To be filled from the chosen direction.
