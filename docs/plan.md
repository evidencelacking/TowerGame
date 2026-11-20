# Plan

Task breakdown for the [roadmap](roadmap.md). Approved 2026-11-10; refreshed 2026-11-16 to match the issues.

Each line is one issue, one Sonnet session, under an hour. "Done" is the acceptance test. IDs
are for planning; the Issue column links each filed task, and GitHub holds its status. Rules and numbers come from
[gameplay-reference.md](gameplay-reference.md); every gameplay issue is checked by the
`gameplay-expert` agent before the owner approves it.

**Each brief names:** the files, what done looks like, and the reference section it replicates.
Every simulation task ships with a headless test.

## M0 Repo and workflow

**Status:** Done.

Copy from the strategy game (`D:\Claude\Game Test`), then fit.

| ID | Task | Done when | Issue |
|---|---|---|---|
| 0.1 | Clone `TowerGame`; Godot 4 project; `.gitignore` (references/, builds, `.godot/`); README with the homage notice; move these docs and the `gameplay-expert` agent in | Opens in Godot, runs an empty scene, pushed | done, not filed |
| 0.2 | Adapt `CLAUDE.md`: values (with Creativity and Fun), rules, sim determinism, clean-room boundary | Owner approves | done, not filed |
| 0.3 | Copy `tools/issue.py`, `setup.py`, `secret_screen.py`, `check.py`; create `type::*` and `status::*` labels | `issue.py` lists issues | done, not filed |
| 0.4 | Copy git hooks; run headless Godot tests | A failing test blocks a commit | done, not filed |
| 0.5 | Copy `.claude/hooks/guard.py`, `session_start.py`, settings | Guard denies owner-only commands | done, not filed |
| 0.6 | Copy agents `issue-reviewer`, `rules-keeper`; skills `godot-dev`, `hook-review` | Agents load and name this repo | done, not filed |
| 0.7 | Copy `docs/workflow.md`, `efficiency.md`, `hooks.md`; add "gameplay-expert review" to the ready step | Docs link correctly | done, not filed |
| 0.8 | `sim_lint.py` (no floats, `randf`, clock time in `scripts/sim/`) and a clean-room check (no reference files, no port paths) | Lint fails on a planted float and a planted reference file | done, not filed |
| 0.9 | CI: headless tests and lint on PRs; PR template | A PR shows a green check | done, not filed |
| 0.10 | File the issues list below and all M1-M2 tasks | Issues in `backlog` | done, not filed |

## M1 Engine skeleton

**Status:** Done except #6 (in owner review).

| ID | Task | Done when | Issue |
|---|---|---|---|
| 1.1 | Sim core: `Tower` state, fixed tick, command queue, seeded RNG | 1,000 ticks identical twice | #1 |
| 1.2 | Clock: 6 periods at different speeds; 2 WD + 1 WE = a quarter; 12 days a year; start 5:00 on 1st WD, 1Q, year 1 | Tests for each rollover | #2 |
| 1.3 | Grid: floors B10 to 100, unit columns, occupancy map | Place and query cells | #3 |
| 1.4 | Full-screen window, resizable, integer pixel scale, windowed/full-screen setting | Sharp at 1080p and 4K | #4 |
| 1.5 | Camera: pan (drag, keys, edges), zoom steps, clamp to the world | Reaches floor 100 and B10 | #5 |
| 1.6 | Native-shape renderer (no image files): sky, ground, grid, a colour per room type; people as small shapes | Aligned at every zoom | #6 |
| 1.7 | HUD: date, period, money, population, stars; pause and 3 speeds | Clock advances and pauses | #7 |
| 1.8 | Headless test harness and tower fixture builder | Used by a test | #8 |
| 1.9 | Launcher `tools/play.py`; re-import on a stale class cache | Game opens from a fresh clone | #111 |

## M2 Build a tower

**Status:** Done.

| ID | Task | Done when | Issue |
|---|---|---|---|
| 2.1 | Room catalogue as data: size, cost, unlock star, removable, placement rules, per-tower limits | Validated in a test against the reference tables | #9 |
| 2.2 | Ground lobby: floor 1, drag to width; 1, 2 or 3 floors tall | Width sets the build limit | #10 |
| 2.3 | Floors: no wider than below, drag to fill, $500 a unit | Width tests | #11 |
| 2.4 | Place office and condo: above ground, buys the floor under it, no overlap | Tests and placement ghost | #12 |
| 2.5 | Placement ghost: valid/invalid, cost, refusal reason, "permanent" warning for non-removable rooms | Hover explains | #13 |
| 2.6 | Bulldoze: free, refuses permanent rooms, removes occupants, refunds condo sales | Tests | #14 |
| 2.7 | Replace tool: bulldoze and place in one action | Test | #15 |
| 2.8 | Money: start $2,000,000 (setting), ledger, refusal when short | Tests | #16 |
| 2.9 | Stairs: place between two floors, not over shafts | Test | #17 |
| 2.10 | Toolbar with sub-menus filtered by star | Builds every M2 item | #18 |
| 2.11 | Message line plus a scrollable message log | Old messages readable | #19 |
| 2.12 | Drag the lobby and floors to any width | Width tests | #127 |

## M3 People and stairs

**Status:** Done.

| ID | Task | Done when | Issue |
|---|---|---|---|
| 3.1 | Person model: home, work, schedule, trip, stress 0-300 | Day plan test | #65 |
| 3.2 | Office tenancy: 6 workers move in when reachable | Unreachable stays empty | #66 |
| 3.3 | Office day: arrive, mid-morning break, lunch, leave; none on weekends | Positions by period | #67 |
| 3.4 | Condo residents (3): out by day, home at night, all week | Test | #68 |
| 3.5 | Route finder: walking and stairs, at most 4 stairs a trip | 5-floor stair trip refused | #69 |
| 3.6 | Stress from travel and waiting; bands under 80, 80-120, over 120 | Band test | #70 |
| 3.7 | Draw people moving, tinted by stress | Visible 8 am commute | #71 |
| 3.8 | Population = people in the tower now | HUD matches sim | #72 |
| 3.9 | Remove people when their room is bulldozed; fixes #73, #74 | Tests | #81 |

## M4 Elevators

**Status:** Done except 4.10 performance and the 4.15 playtest.

| ID | Task | Done when | Issue |
|---|---|---|---|
| 4.1 | Shaft: up to 30 floors including basements; 24 shafts in all | Limit tests | #89 |
| 4.2 | Resize shaft by drag; per-floor stop on/off | Disabled floor skipped | #90 |
| 4.3 | Local elevator cars: up to 8 (by star), 17 per car, home floor | Limit tests | #91 |
| 4.4 | Car motion in integer ticks: travel, stop, doors | Arrival time test | #92 |
| 4.5 | Calls and dispatch: nearest car, direction | Two calls in order | #93 |
| 4.6 | Boarding and unloading; full cars pass | 18th person waits | #94 |
| 4.7 | Routes use elevators; transfers only at lobbies, one per trip | Tests | #95 |
| 4.8 | Preference: escalator, waiting car, then stairs; waiting stress | Tests | #96 |
| 4.9 | Draw shafts, cars, queues (left goes up, right goes down) | Rush-hour queue visible | #97 |
| 4.10 | Performance: 2,000 people at top speed | Target frame rate held | #108 |
| 4.11 | Elevator build controls: drag shafts, resize by end, click for stops, add cars | Lobby, floors, shaft and car built by mouse; people ride | #107 |
| 4.12 | Elevator speed: full height in about 4 sim minutes | Exact tick tests | #103 |
| 4.13 | Idle cars return to their home floor | Test | #109 |
| 4.14 | Escalator placement and links over rooms (pulled forward from 8.4) | Tests | #125, #126 |
| 4.15 | Owner playtest: elevators end to end | Owner reports results | #110 |

## M5 Economy and grades

**Status:** In progress.

| ID | Task | Done when | Issue |
|---|---|---|---|
| 5.1 | Quality = 300 - average stress; A over 200, B 150-200, C under 150 | Threshold tests | #113 |
| 5.2 | At rest period: A brings a friend, C leaves; offices leave after a red day | Tests | #114 |
| 5.3 | 4 rent levels and their effect on tolerance | High rent lowers grade | #115 |
| 5.4 | Office rent on the 1st WD; quarterly running costs (elevators, services) | Balance after a quarter | #116 |
| 5.5 | Noise: offices disturb condos and hotels, not each other; radiates above, below, beside | Tests | #117 |
| 5.6 | Word of mouth: complaints spread to nearby tenants | C room lowers neighbours | #118 |
| 5.7 | Complaint reasons: noisy neighbours, elevator too far, rent too high | Shown in info window | #119 |
| 5.8 | Room info window: occupants, grade bar, rent, complaint | Rent change applies | #120 |
| 5.9 | Person info window: name, from, to, stress; rename | Opens on click | #121 |
| 5.10 | Finance window: income and costs by kind and quarter | Matches ledger | #122 |
| 5.11 | Star 2 rule: population 300 | Promotion test | #123 |
| 5.12 | Save and load: versioned state; autosave every quarter | Round trip equals state | #124 |
| 5.13 | Owner playtest: economy and grades | Owner reports results | not filed |

## M6 Hotel and commerce

**Status:** Filed 2026-11-16; in backlog for gameplay review.

Reordered 2026-11-16: the service elevator comes first because housekeeping uses it, and customer
grades follow fast food because the room info window (#120) needs them.

| ID | Task | Done when | Issue |
|---|---|---|---|
| 6.1 | Service elevator (staff only), 17 per car | A housekeeper rides it, a guest never does | #145 |
| 6.2 | Single, twin, suite: check in evening, out morning, pay daily | One-night test; income in the finance window | #146 |
| 6.3 | Dirty after check-out; unrentable until cleaned | Test | #147 |
| 6.4 | Housekeeping: 6 staff, one per floor, about 6 floors, service elevators only | Cleaned by noon | #148 |
| 6.5 | Pests: dirty too long, spread along the floor, fix is demolish | Test | #149 |
| 6.6 | Fast food: lunch and snacks, 5 kinds, daily sales, cap 30 | Test | #150 |
| 6.7 | Customer grades (A/B/C from daily counts) and next-day change; feed the room info window bar | Threshold tests | #151 |
| 6.8 | Restaurant: dinner, linger, 5 kinds, cap 40 | Test | #152 |
| 6.9 | Retail shop: 11 kinds, quarterly rent, leaves if C | Test | #153 |
| 6.10 | Visitors from outside by time of day; weekend shopping peak | Counts by period | #154 |
| 6.11 | Native-shape look for each new room kind (no image files; art waits for M10) | Distinct at every zoom | #155 |
| 6.12 | Debug unlock-all switch, kept apart from normal play (pulled forward from #39) | Off by default; a 3-star room placeable with it on | #156 |
| 6.13 | Owner playtest: hotel and commerce | Owner reports results | #157 |

## M7 Stars and services

**Status:** Filed 2026-11-16; in backlog for gameplay review.

Reordered 2026-11-16: the old 7.2 (unlocks, limits, costs) is already in the room catalogue and
toolbar, so it joins the promotion moment; demand messages move up because the 3-star demands
arrive at once; a simple VIP comes forward from 9.4 so star 4 can be reached before M9. Hotel
guests always count toward population (owner, #37).

| ID | Task | Done when | Issue |
|---|---|---|---|
| 7.1 | Star rules 3-5 as data: 3 = 1,000 + security; 4 = 5,000 + medical, recycling, more than one suite, good VIP; 5 = 10,000 + metro (rule only; metro in 11.3) | Promotion tests per rank | #166 |
| 7.2 | Promotion moment: banner, message, sound hook; toolbar shows new unlocks | Shows once; new rooms appear | #167 |
| 7.3 | Demand messages ("needs security", "needs recycling", "needs parking" ...) | Shown and cleared | #168 |
| 7.4 | Security office: staff, outside emergency stairs only; coverage by distance | Coverage test | #169 |
| 7.5 | Medical centre: demand from office workers | Demand message clears | #170 |
| 7.6 | Recycling: 2 floors, underground, must touch others, fills daily, truck empties at morning, full = idle; service elevator reach rule (#162) | Tests | #171 |
| 7.7 | Parking: ramp column under the ground lobby, spaces chain to it, broken chain marked; demand from offices (3 stars) and one per suite | Tests | #172 |
| 7.8 | Simple VIP visit: stays in a suite, verdict gates star 4, retries later; no dialogs (pulled forward from 9.4) | Test | #173 |
| 7.9 | Native-shape look for each M7 room kind | Distinct at every zoom | #174 |
| 7.10 | Owner playtest: stars and services | Owner reports results | #175 |

## M8 Big-tower transport

| ID | Task | Done when | Issue |
|---|---|---|---|
| 8.1 | Sky lobby: only floors 15, 30 ... 90 | Test | #182 |
| 8.2 | Express: any height, lobbies and all basements, 36 per car, faster (speed constants exist from #103) | Tests | #183 |
| 8.2b | Elevator shafts: click to place, drag either end, machine rooms above and below, missing floors built at the floor price | Tests | #228 |
| 8.3 | Routes across a 100-floor tower: express to sky lobby, one change | Tests | #184 |
| 8.4 | Escalator rules (placement done in #125, #126): commercial, lobby or empty floors; at most 7 a trip; shared customers | Tests | #185 |
| 8.5 | Shared stair and escalator limit (64) | Test | #186 |
| 8.6 | Elevator panel: car columns, home floors, floor on/off | Edits apply | #187 |
| 8.7 | Schedules by WD/WE and period: express to top/bottom, response distance, departure wait 0-90 s | Test each | #188 |
| 8.8 | Panel preview of one shaft, explained in plain words | Shows cars and riders | #189 |
| 8.9 | M8 owner playtest | Owner reports results | #192 |

Performance and the optional waiting stress moved to Later (owner, 2026-11-19).

## M9 Events

Rows 9.4 to 9.8 (#219 to #223) are held until after M10 (owner, 2026-11-19): more events once the graphics are better.

Values in brackets on each issue are the gameplay expert's recommendations, chosen by the coordinator.

| ID | Task | Done when | Issue |
|---|---|---|---|
| 9.1 | Event scheduler: own seeded stream, rolls per period, choices as commands | Reproducible | #214 |
| 9.1b | Event dialogs: notice, choices, time left | Choice queues a command | #215 |
| 9.1c | Security response: guards travel to the event floor | Tests | #216 |
| 9.2 | Fire: security and 3 stars; spreads sideways and up; $500,000 rescue | Both outcomes | #217 |
| 9.3 | Threat (our own version): pay $200,000, or search before 13:00; a miss destroys 5 floors | All outcomes | #218 |
| 9.4 | VIP as a full event: arrival choice, verdict reasons (simple VIP in 7.8) | Test | #219 |
| 9.5 | Treasure found while building underground: one seeded spot, B3-B8 | Seeded test | #220 |
| 9.6 | Rain: fewer visitors, food hit hardest | Test | #221 |
| 9.7 | Seasonal fly-past on a Q4 weekend night (our own character) | Visible | #222 |
| 9.8 | Alert markers at the screen edge; the overview map reuses them | Visible | #223 |
| 9.9 | M9 owner playtest | Owner reports results | #224 |

## M10 Look, sound and UI

Starts only once the game is playable on native shapes (owner, 2026-11-10). All art is
original; nothing is taken from the original game's art or animation. Art is drawn by code
(owner, 2026-11-19): each room kind is a recipe of palette, frame, furniture shapes and spots,
drawn at a low native resolution and scaled up by whole numbers. No image files until the
zoom-detail sprites in Later. Every activity gets a visual: if the sim knows someone is doing
something, the view shows it. Animation reads sim state only and adds no saved state.

| ID | Task | Done when | Issue |
|---|---|---|---|
| 10.1 | Feel rules in our own words (cutaway boxes, readable walls, colour per kind, lit rooms in use, sky carries the time) and 3 code-drawn mock-ups of one floor slice; owner picks; name the game | Decision recorded | #240 |
| 10.2 | Renderer: low-res canvas at integer scale, palette, recipe system (frame, furniture, spots, empty and in-use looks), batched drawing; replaces the native-shape look (absorbs #143) | Sharp at 1080p and 4K; test: every room kind has a recipe | #143 |
| 10.3 | Recipes, batch 1: lobby, offices, condos, hotel rooms, housekeeping | Owner approves by eye; tests: in-use and empty looks differ | #241 |
| 10.4 | Recipes, batch 2: food, shops, services, parking, recycling, transport (stairs and escalator slopes, shafts, cars) | Owner approves by eye | #242 |
| 10.5 | People: figures about 3x7 native px with a colour per type and stress marks, a 2-frame walk, a standing pose on escalators, a stepping cycle on stairs, smooth diagonal movement on stairs and escalator legs, smoothing between ticks | Test: height moves smoothly floor to floor | #243 |
| 10.6 | Activities in rooms: occupants on recipe spots chosen by id (desks, tables, beds, sofas), shown doing what the sim says (working, at lunch, eating, sleeping with lights off, cleaning, queueing, shopping); small idle motion from id and period | Tests: spots stay inside the room; same moment draws the same | #244 |
| 10.7 | Event and service visuals: fire and smoke, guards moving, rescue craft, threat search, VIP, treasure, rain, fly-past, elevator doors | Each M9 event has a visual | #245 |
| 10.8 | Sky and light: day/night by period, lit windows, rain | Smooth over a day | #246 |
| 10.9 | Overview map with Eval, Rent, Hotel and Problems filters; click jumps the camera; the Eval filter is #142 | Works | #142 |
| 10.10 | Bulk rent: set rent for a selection, a floor or a room type | One action changes many | #28 |
| 10.11 | Sound: ambience, UI, elevator, crowd, events (original or licensed) | Licence per file | #247 |
| 10.12 | Settings: resolution, full screen, UI scale, volume, keys, starting funds | Persist | #248 |

## Our own: M12 to M14

Owner (2026-11-19): the game plays close to the genre but rudimentary; the last phase makes it ours.
M12 and M13 start now, ahead of M11; M14 is the headline feature once they land. All of it is our own
design (nothing here comes from the original), deterministic in `scripts/sim`, every rule tested.

### M12 Living tower: people with stories

| ID | Task | Done when | Issue |
|---|---|---|---|
| 12.1 | Identity: every person has a name, age band and job title, derived from id and tower seed by our own syllable tables (no saved state) | Same person, same name; tests || #285 |
| 12.2 | Mood 0-100 per person from waits, noise, room grade, crowding and events; drives stay or leave in place of raw stress; shown in the person window | Tests; save bump || #286 |
| 12.3 | Life events: couples form, move in together, a child joins the household, promotions, retirements, leaving town; rare, seeded, per day | Tests; save bump || #287 |
| 12.4 | Tower news: a ticker of life and tower events with names; click a story to jump to the person or room | Works || #288 |
| 12.5 | Follow a person: the camera tracks them; the person window shows their day plan and recent stories | Works || #289 |
| 12.6 | Thought icons: small mood and need icons over people (waiting too long, noisy, happy, hungry) | Owner approves by eye || #290 |

### M13 Neighbourhoods and synergies

| ID | Task | Done when | Issue |
|---|---|---|---|
| 13.1 | New kinds batch 1: gym, daycare, clinic (cost, size, star, staff, recipe) | Tests || #291 |
| 13.2 | New kinds batch 2: rooftop garden, nightclub, co-working | Tests || #292 |
| 13.3 | Synergies: each kind boosts or harms neighbours within a reach (daycare lifts condo demand, gym lifts office mood, clinic speeds recovery, garden feeds restaurants, nightclub earns at night but annoys condos); integers, deterministic; the ghost previews the effect | Tests || #293 |
| 13.4 | Synergy overlay: a map filter showing boosts and harms per room | Works || #294 |
| 13.5 | Districts: a cluster of rooms that boost each other is named and gets a district bonus | Tests || #295 |
| 13.6 | Joined suites, step 2: a suite is one tenant with rent and staff scaled by width; merge and split | Tests; save bump | #276 |

### M14 Twin towers and sky bridges (headline, after M12 and M13)

| ID | Task | Done when | Issue |
|---|---|---|---|
| 14.1 | A second tower on the lot, built and run like the first | Tests |  |
| 14.2 | Sky bridges between the towers at sky-lobby floors | Tests |  |
| 14.3 | Routing, rents and evaluation across both towers | Tests |  |
| 14.4 | The skyline and city around the towers grow with the star rating | Owner approves by eye |  |

### M15 Detailed art (owner, 2026-11-19; direction G Lit)

A second graphics style, chosen by a setting; Classic stays as it is. Detailed draws at double density
(16 px per column, 64 px per floor) in the G Lit direction: crisp 2x pixel art with Godot 2D lighting.
All art original and drawn by code.

| ID | Task | Done when | Issue |
|---|---|---|---|
| 15.1 | Three mock-ups (E Illustrated, F Rich pixel, G Lit); owner picks | Owner picked G Lit | #300 |
| 15.2 | Graphics setting (Classic / Detailed) and renderer split into style backends | Tests; ui_test | #301 |
| 15.3 | Detailed recipes batch 1: lobby, offices, condo, hotel, housekeeping | Owner approves by eye | #302 |
| 15.4 | Detailed recipes batch 2: food, retail, services, parking, culture, links, shafts, cars | Owner approves by eye | #303 |
| 15.5 | Detailed animated people with variety by id, age and job | Owner approves by eye | #304 |
| 15.6 | Lighting and atmosphere at full-tower scale, weather | Frame budget held; owner approves | #305 |
| 15.7 | Exterior and city: facade, roof, street, parallax skyline | Owner approves by eye | #306 |
| 15.8 | Detailed UI skin and performance pass | Frame-rate report | #307 |

## M11 Full game

| ID | Task | Done when | Issue |
|---|---|---|---|
| 11.1 | Movie theatre: 2 floors, film choice (new or classic, cost), top in, bottom out, shoppers within 5 floors | Test |  |
| 11.2 | Party hall: afternoon parties, needs hotel rooms | Test |  |
| 11.3 | Metro: 3 floors, bottom at B10, nothing below, one per tower; visitors shop underground; B10 reserved | Tests |  |
| 11.4 | Cathedral at floor 100 (our own landmark) | Placement test |  |
| 11.5 | Top rank: 15,000 + landmark + 5 stars, then a weekend wedding and our own celebration | Test and scene |  |
| 11.6 | Tutorial: first tower to 2 stars | Owner completes it |  |
| 11.7 | Balance run: scripted headless 10-year towers per strategy (offices-only, condos, hotels) | Money and population report |  |
| 11.8 | Release builds: Windows zip; Mac and Linux exports checked | Launch |  |

## Later

Performance work and optional features, after the features above (owner, 2026-11-19).

| ID | Task | Done when | Issue |
|---|---|---|---|
| L.1 | Performance: 15,000 people (was 8.9) | Target frame rate held | #190 |
| L.2 | Tenant direction bias and rush-hour waiting stress (optional, was 8.10) | Tests | #191 |
| L.3 | Zoom detail: when zoomed in on a room, draw more detail (finer furniture, larger people with faces and clothes); code first, hand-made sprites if code is not enough | Owner approves by eye |  |
| L.4 | Bigger people as a setting or at higher zoom, grown from the 10.5 figures | Owner approves by eye |  |
| L.5 | Room and option variety beyond the original: new room kinds, variants of each kind (styles, sizes, upgrades), more tenant choices; each new kind gets a recipe | Owner picks the list |  |

## Issues list from the player guides

Obvious or required changes found in the player guides. They are folded into the tasks above
(right column) and filed as issues in task 0.10.

| # | Type | Issue | Why | Task | Filed |
|---|---|---|---|---|---|
| 1 | design | Record the star requirements table | Exact rules for ranks 2-5 and the top rank | 5.11, 7.1 | #20 |
| 2 | design | Record costs, unlock ranks and per-tower limits as data | Every placement task needs them | 2.1 | #21 |
| 3 | design | Apply the owner's conflict rulings: local 17 and express 36 per car, one transfer, 7 escalators, rescue and treasure $500,000, ransom $200,000 | Decided 2026-11-10 | 2.1 | #22 |
| 4 | feature | Permanent rooms: refuse bulldoze, warn before placing | Lobby, floors, security, housekeeping, medical, theatre, metro, cathedral | 2.5, 2.6 | #23 |
| 5 | feature | Lobby only on floor 1 and every 15th floor; 2- or 3-floor ground lobby | Placement rule and a known option | 2.2, 8.1 | #24 |
| 6 | feature | Replace tool | Players relied on the shift-click trick | 2.7 | #25 |
| 7 | feature | Message log | Messages flashed past too fast | 2.11 | #26 |
| 8 | feature | Autosave | Players lost towers to crashes | 5.12 | #27 |
| 9 | feature | Bulk rent tool | Rent changed one room at a time was the top complaint | 10.10 | #28 |
| 10 | feature | Complaint reasons in info windows | Players had to guess why tenants left | 5.7 | #29 |
| 11 | feature | Recycling rules: 2 floors, touching, fills and empties daily | Missing from the first plan | 7.6 | #30 |
| 12 | feature | Parking ramp column and chained spaces | Missing from the first plan | 7.7 | #31 |
| 13 | feature | Metro footprint B8-B10 and keep B10 clear | Avoid the original's dead-end | 11.3 | #32 |
| 14 | feature | Weekend wedding finale | The top rank needs it | 11.5 | #33 |
| 15 | feature | Rain and seasonal fly-past events | Missing from the first plan | 9.6, 9.7 | #34 |
| 16 | design | Don't replicate bugs: double funds, office escalators; starting funds becomes a setting | Faithful to intent, not to bugs | 2.8, 8.4 | #35 |
| 17 | design | Lowest-rent exploit and rent-toggle reset: replicate, then review in M12 | Known balance holes | 5.3 | #36 |
| 18 | design | Hotel guests in population after 3 stars | Unverified claim; owner: always count | 7.1 | #37 |
| 19 | test | Balance runs replay the guides' strategies (offices-only, condos-first) | Checks the climb feels like the original | 11.7 | #38 |
| 20 | process | `gameplay-expert` reviews each gameplay issue before `ready` | Faithful replication | 0.7 | process, no issue |
| 21 | feature | Our own cheats (debug money, unlock all, instant build), kept apart from normal play | Owner wants them; the original's bug cheats are not replicated | M12+ | #39 |
