# Art standard

Status: the owner chose direction A's warm colours with B's thin-line styling (2026-11-19, #240),
shown as mock-up D (`mockups/art_d.tscn`). The renderer (M10.2) draws from the palette below.
All wording is ours.

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
6. **People are small but readable.** About 6x16 native px, half a floor tall (`VC.FIGURE_W`,
   `VC.FIGURE_H`; every pose derives from the pair). A hair line, a skin face, a shirt in the type
   colour and two legs. Alone they are people, together a crowd in motion.
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
| D32 | `art_d32.tscn` | D at 32 px per floor with detailed furniture and 4x9 figures (the renderer now draws 6x16) (`floor_h`, `detail` on the scene). |
| D40 | `art_d40.tscn` | The same detail at 40 px per floor, to judge how tall a floor needs to be. |

### Detailed directions (M15, issue #300)

Double density (16 px per column, 64 px per floor), one tower slice with lobby, office, condo,
restaurant, stairs, escalator, elevator shaft and car, and 12x32 people with faces. All drawn by code
(`mockups/detail_drawer.gd` on `detail_prims.gd`), original art. N or Space toggles day and night.

| Direction | Scene | Look |
|---|---|---|
| E | `art_e.tscn` | Illustrated: smooth anti-aliased shapes, gradients, soft shadows, rounded forms. |
| F | `art_f.tscn` | Rich pixel: crisp 2x pixel art, ordered dithering, selective outlines, 3-tone furniture. |
| G | `art_g.tscn` | Lit: F's shapes with Godot 2D lighting, so lamps and windows glow at night. |

Direction G was chosen (#300). Detailed batch 1 (#302: lobby, office, condo, hotel rooms, housekeeping) is drawn by
`scripts/view/detail_rooms.gd` on `detail_prims.gd` and `detail_scenes.gd`, ported from the G Lit mock-up and placed from the recipes' spots, inside the same world
rects, shown on a 2x static canvas (`TowerRenderer._apply_density`), so spots, camera and picking are unchanged. Use an even
camera zoom to keep sub-pixels crisp. Captures: `docs/mockups/detailed_batch1_day.png` and `_night.png`
(`tools/capture_recipes.gd set=1 detailed=1 time=35 zoom=4`; `time=2` for night).
Night under Detailed is lighting (#305), not darker paint: the renderer multiplies the static canvas by the sky's ambient colour
(`detail_light.gd`, the mock-up's day and night ambients) and an additive glow node above it paints each lit room's lamp pools, window and
screen glow from one radial texture, clipped to the room (no per-room PointLight2D). Empty rooms stay dark; a sleeper keeps a bedside lamp.

Captures: `docs/mockups/art_e_day.png` ... `art_g_night.png`, made with `-- --capture=docs/mockups`.

Launch (PowerShell): `python D:\Claude\TowerGame\tools\play.py --scene res://mockups/art_a.tscn`.
Captures: `docs/mockups/art_<x>_day.png` and `_night.png`, made by running a scene windowed with
`-- --capture=<dir>`. Headless Godot has no renderer, so capture needs a window.

## Palette and line style (direction D)

The source of truth is style 3 (D) in `mockups/art_drawer.gd` until the renderer takes it over.

| Use | Colour |
|---|---|
| Day sky, top to horizon | `#5cb8f0` to `#f8e4a8` |
| Night sky, top to horizon | `#1a1440` to `#68305c` |
| Walls, slabs, outlines | `#3a2216`, `#22120c`, `#160a06` |
| Room hues (one per kind family) | `#e8b458`, `#58a0e0`, `#e0648c`, `#f08030`; new kinds add hues of the same warmth and saturation |
| Shaft, car | `#2a1a12`, `#e4c43c` |
| Ground, earth | `#4a8a30`, `#5a3a22` |
| People | `#d03030`, `#3050c8`, `#30a040`, `#f0f0f0`, `#8a38a8`; skin `#f0c090` |
| Lamp light | `#fff0a0` |

Line style:
- Furniture is drawn as 1-pixel lines in the room hue darkened by about 45%, not filled and
  outlined blocks. No chunky outlines.
- Each room has a thin dark frame; each slab has a 1-pixel warm highlight line.
- Empty rooms dim to about 45% by day and 80% by night; in-use rooms are full colour with a
  lighter band under the ceiling.

In the renderer (`scripts/view/palette.gd`, `room_recipes.gd`): D is palette index 3 and the default;
A, B and C stay selectable by `Palette.DEFAULT_INDEX`. The renderer draws at 8 px per column and
32 px per floor (`VC.CELL_W`, `VC.CELL_H`), matching `art_d32.tscn`. `docs/mockups/renderer_d.png` is the real
renderer drawing a small tower.
