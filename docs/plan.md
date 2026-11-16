# Plan

Task breakdown for the [roadmap](roadmap.md). Draft for the owner's review, 2026-11-10.

Each line is one issue, one Sonnet session, under an hour. "Done" is the acceptance test. IDs
are for planning; issue numbers replace them when filed. Rules and numbers come from
[gameplay-reference.md](gameplay-reference.md); every gameplay issue is checked by the
`gameplay-expert` agent before the owner approves it.

**Each brief names:** the files, what done looks like, and the reference section it replicates.
Every simulation task ships with a headless test.

## M0 Repo and workflow

Copy from the strategy game (`D:\Claude\Game Test`), then fit.

| ID | Task | Done when |
|---|---|---|
| 0.1 | Clone `TowerGame`; Godot 4 project; `.gitignore` (references/, builds, `.godot/`); README with the homage notice; move these docs and the `gameplay-expert` agent in | Opens in Godot, runs an empty scene, pushed |
| 0.2 | Adapt `CLAUDE.md`: values (with Creativity and Fun), rules, sim determinism, clean-room boundary | Owner approves |
| 0.3 | Copy `tools/issue.py`, `setup.py`, `secret_screen.py`, `check.py`; create `type::*` and `status::*` labels | `issue.py` lists issues |
| 0.4 | Copy git hooks; run headless Godot tests | A failing test blocks a commit |
| 0.5 | Copy `.claude/hooks/guard.py`, `session_start.py`, settings | Guard denies owner-only commands |
| 0.6 | Copy agents `issue-reviewer`, `rules-keeper`; skills `godot-dev`, `hook-review` | Agents load and name this repo |
| 0.7 | Copy `docs/workflow.md`, `efficiency.md`, `hooks.md`; add "gameplay-expert review" to the ready step | Docs link correctly |
| 0.8 | `sim_lint.py` (no floats, `randf`, clock time in `scripts/sim/`) and a clean-room check (no reference files, no port paths) | Lint fails on a planted float and a planted reference file |
| 0.9 | CI: headless tests and lint on PRs; PR template | A PR shows a green check |
| 0.10 | File the issues list below and all M1-M2 tasks | Issues in `backlog` |

## M1 Engine skeleton

| ID | Task | Done when |
|---|---|---|
| 1.1 | Sim core: `Tower` state, fixed tick, command queue, seeded RNG | 1,000 ticks identical twice |
| 1.2 | Clock: 6 periods at different speeds; 2 WD + 1 WE = a quarter; 12 days a year; start 5:00 on 1st WD, 1Q, year 1 | Tests for each rollover |
| 1.3 | Grid: floors B10 to 100, unit columns, occupancy map | Place and query cells |
| 1.4 | Full-screen window, resizable, integer pixel scale, windowed/full-screen setting | Sharp at 1080p and 4K |
| 1.5 | Camera: pan (drag, keys, edges), zoom steps, clamp to the world | Reaches floor 100 and B10 |
| 1.6 | Native-shape renderer (no image files): sky, ground, grid, a colour per room type; people as small shapes | Aligned at every zoom |
| 1.7 | HUD: date, period, money, population, stars; pause and 3 speeds | Clock advances and pauses |
| 1.8 | Headless test harness and tower fixture builder | Used by a test |

## M2 Build a tower

| ID | Task | Done when |
|---|---|---|
| 2.1 | Room catalogue as data: size, cost, unlock star, removable, placement rules, per-tower limits | Validated in a test against the reference tables |
| 2.2 | Ground lobby: floor 1, drag to width; 1, 2 or 3 floors tall | Width sets the build limit |
| 2.3 | Floors: no wider than below, drag to fill, $500 a unit | Width tests |
| 2.4 | Place office and condo: above ground, buys the floor under it, no overlap | Tests and placement ghost |
| 2.5 | Placement ghost: valid/invalid, cost, refusal reason, "permanent" warning for non-removable rooms | Hover explains |
| 2.6 | Bulldoze: free, refuses permanent rooms, removes occupants, refunds condo sales | Tests |
| 2.7 | Replace tool: bulldoze and place in one action | Test |
| 2.8 | Money: start $2,000,000 (setting), ledger, refusal when short | Tests |
| 2.9 | Stairs: place between two floors, not over shafts | Test |
| 2.10 | Toolbar with sub-menus filtered by star | Builds every M2 item |
| 2.11 | Message line plus a scrollable message log | Old messages readable |

## M3 People and stairs

| ID | Task | Done when |
|---|---|---|
| 3.1 | Person model: home, work, schedule, trip, stress 0-300 | Day plan test |
| 3.2 | Office tenancy: 6 workers move in when reachable | Unreachable stays empty |
| 3.3 | Office day: arrive, mid-morning break, lunch, leave; none on weekends | Positions by period |
| 3.4 | Condo residents (3): out by day, home at night, all week | Test |
| 3.5 | Route finder: walking and stairs, at most 4 stairs a trip | 5-floor stair trip refused |
| 3.6 | Stress from travel and waiting; bands under 80, 80-120, over 120 | Band test |
| 3.7 | Draw people moving, tinted by stress | Visible 8 am commute |
| 3.8 | Population = people in the tower now | HUD matches sim |

## M4 Elevators

| ID | Task | Done when |
|---|---|---|
| 4.1 | Shaft: up to 30 floors including basements; 24 shafts in all | Limit tests |
| 4.2 | Resize shaft by drag; per-floor stop on/off | Disabled floor skipped |
| 4.3 | Local elevator cars: up to 8 (by star), 17 per car, home floor | Limit tests |
| 4.4 | Car motion in integer ticks: travel, stop, doors | Arrival time test |
| 4.5 | Calls and dispatch: nearest car, direction | Two calls in order |
| 4.6 | Boarding and unloading; full cars pass | 18th person waits |
| 4.7 | Routes use elevators; transfers only at lobbies, one per trip | Tests |
| 4.8 | Preference: escalator, waiting car, then stairs; waiting stress | Tests |
| 4.9 | Draw shafts, cars, queues (left goes up, right goes down) | Rush-hour queue visible |
| 4.10 | Performance: 2,000 people at top speed | Target frame rate held |
| 4.11 | Elevator build controls: drag shafts, resize by end, click for stops, add cars | Lobby, floors, shaft and car built by mouse; people ride |

## M5 Economy and grades

| ID | Task | Done when |
|---|---|---|
| 5.1 | Quality = 300 - average stress; A over 200, B 150-200, C under 150 | Threshold tests |
| 5.2 | At rest period: A brings a friend, C leaves; offices leave after a red day | Tests |
| 5.3 | 4 rent levels and their effect on tolerance | High rent lowers grade |
| 5.4 | Office rent on the 1st WD; quarterly running costs (elevators, services) | Balance after a quarter |
| 5.5 | Noise: offices disturb condos and hotels, not each other; radiates above, below, beside | Tests |
| 5.6 | Word of mouth: complaints spread to nearby tenants | C room lowers neighbours |
| 5.7 | Complaint reasons: noisy neighbours, elevator too far, rent too high | Shown in info window |
| 5.8 | Room info window: occupants, grade bar, rent, complaint | Rent change applies |
| 5.9 | Person info window: name, from, to, stress; rename | Opens on click |
| 5.10 | Finance window: income and costs by kind and quarter | Matches ledger |
| 5.11 | Star 2 rule: population 300 | Promotion test |
| 5.12 | Save and load: versioned state; autosave every quarter | Round trip equals state |

## M6 Hotel and commerce

| ID | Task | Done when |
|---|---|---|
| 6.1 | Single, twin, suite: check in evening, out morning, pay daily | One-night test |
| 6.2 | Dirty after check-out; unrentable until cleaned | Test |
| 6.3 | Housekeeping: 6 staff, one per floor, about 6 floors, service elevators only | Cleaned by noon |
| 6.4 | Pests: dirty too long, spread along the floor, fix is demolish | Test |
| 6.5 | Fast food: lunch and snacks, 5 kinds, daily sales, cap 30 | Test |
| 6.6 | Restaurant: dinner, linger, 5 kinds, cap 40 | Test |
| 6.7 | Customer grades (A/B/C from daily counts) and next-day change | Threshold tests |
| 6.8 | Retail shop: 11 kinds, quarterly rent, leaves if C | Test |
| 6.9 | Visitors from outside by time of day; weekend shopping peak | Counts by period |
| 6.10 | Service elevator (staff only) | Test |
| 6.11 | Placeholder art for each room kind | Distinct |

## M7 Stars and services

| ID | Task | Done when |
|---|---|---|
| 7.1 | Star rules as data: 3 = 1,000 + security; 4 = 5,000 + medical, recycling, more than one suite, good VIP; 5 = 10,000 + metro | Promotion tests per rank |
| 7.2 | Unlocks, limits and costs per star | Toolbar changes on promotion |
| 7.3 | Promotion moment: banner, message, sound hook | Shows once |
| 7.4 | Security office: staff, outside emergency stairs only; coverage by distance | Coverage test |
| 7.5 | Medical centre: demand from office workers | Demand message clears |
| 7.6 | Recycling: 2 floors, underground, must touch others, fills daily, truck empties at morning, full = idle, served by service elevator | Tests |
| 7.7 | Parking: ramp column under the ground lobby, spaces chain to it, broken chain marked; demand from offices (3 stars) and one per suite | Tests |
| 7.8 | Demand messages ("needs recycling", "needs parking") | Shown and cleared |
| 7.9 | Decide hotel guests in population after 3 stars (*unverified*) | Owner decision recorded |

## M8 Big-tower transport

| ID | Task | Done when |
|---|---|---|
| 8.1 | Sky lobby: only floors 15, 30 ... 90 | Test |
| 8.2 | Express: any height, lobbies and all basements, 36 per car, faster | Tests |
| 8.3 | Routes across a 100-floor tower: express to sky lobby, one change | Tests |
| 8.4 | Escalator: commercial, lobby or empty floors; at most 7 a trip; shared customers | Tests |
| 8.5 | Shared stair and escalator limit (64) | Test |
| 8.6 | Elevator panel: car columns, home floors, floor on/off | Edits apply |
| 8.7 | Schedules by WD/WE and period: express to top/bottom, response distance, departure wait 0-90 s | Test each |
| 8.8 | Panel preview of one shaft, explained in plain words | Shows cars and riders |
| 8.9 | Performance: 15,000 people | Target frame rate held |

## M9 Events

| ID | Task | Done when |
|---|---|---|
| 9.1 | Event system: seeded, scheduled and random, dialogs with choices | Reproducible |
| 9.2 | Fire: only with security; spreads sideways and up; security travel time; paid rescue | Both outcomes |
| 9.3 | Threat event (our own version): pay, or search floor by floor before the deadline; a miss destroys about 5 floors | Both outcomes |
| 9.4 | VIP stays in a suite; verdict gates star 4; retries later | Test |
| 9.5 | Treasure found while building underground | Seeded probability test |
| 9.6 | Rain: fewer visitors, food hit hardest | Test |
| 9.7 | Seasonal fly-past in Q4 at night (our own character) | Visible |
| 9.8 | Alert markers on the overview map | Visible |

## M10 Look, sound and UI

Starts only once the game is playable on native shapes (owner, 2026-11-10). All art is
original; nothing is taken from the original game's art or animation.

| ID | Task | Done when |
|---|---|---|
| 10.1 | Art direction: 3 mock-ups of one floor slice; owner picks; name the game | Decision recorded |
| 10.2 | Art standard and `art-keeper` agent | Approved |
| 10.3 | Sprite sets, one task each: lobby, offices, condos, hotel, food, shops, services, transport, people, sky | Each passes art-keeper |
| 10.4 | Overview map with Eval, Rent, Hotel and Problems filters; click jumps the camera | Works |
| 10.5 | Bulk rent: set rent for a selection, a floor or a room type | One action changes many |
| 10.6 | Day/night sky by period | Smooth over a day |
| 10.7 | Sound: ambience, UI, elevator, crowd, events (original or licensed) | Licence per file |
| 10.8 | Settings: resolution, full screen, UI scale, volume, keys, starting funds | Persist |

## M11 Full game

| ID | Task | Done when |
|---|---|---|
| 11.1 | Movie theatre: 2 floors, film choice (new or classic, cost), top in, bottom out, shoppers within 5 floors | Test |
| 11.2 | Party hall: afternoon parties, needs hotel rooms | Test |
| 11.3 | Metro: 3 floors, bottom at B10, nothing below, one per tower; visitors shop underground; B10 reserved | Tests |
| 11.4 | Cathedral at floor 100 (our own landmark) | Placement test |
| 11.5 | Top rank: 15,000 + landmark + 5 stars, then a weekend wedding and our own celebration | Test and scene |
| 11.6 | Tutorial: first tower to 2 stars | Owner completes it |
| 11.7 | Balance run: scripted headless 10-year towers per strategy (offices-only, condos, hotels) | Money and population report |
| 11.8 | Release builds: Windows zip; Mac and Linux exports checked | Launch |

## Issues list from the player guides

Obvious or required changes found in the player guides. They are folded into the tasks above
(right column) and filed as issues in task 0.10.

| # | Type | Issue | Why | Task |
|---|---|---|---|---|
| 1 | design | Record the star requirements table | Exact rules for ranks 2-5 and the top rank | 5.11, 7.1 |
| 2 | design | Record costs, unlock ranks and per-tower limits as data | Every placement task needs them | 2.1 |
| 3 | design | Apply the owner's conflict rulings: local 17 and express 36 per car, one transfer, 7 escalators, rescue and treasure $500,000, ransom $200,000 | Decided 2026-11-10 | 2.1 |
| 4 | feature | Permanent rooms: refuse bulldoze, warn before placing | Lobby, floors, security, housekeeping, medical, theatre, metro, cathedral | 2.5, 2.6 |
| 5 | feature | Lobby only on floor 1 and every 15th floor; 2- or 3-floor ground lobby | Placement rule and a known option | 2.2, 8.1 |
| 6 | feature | Replace tool | Players relied on the shift-click trick | 2.7 |
| 7 | feature | Message log | Messages flashed past too fast | 2.11 |
| 8 | feature | Autosave | Players lost towers to crashes | 5.12 |
| 9 | feature | Bulk rent tool | Rent changed one room at a time was the top complaint | 10.5 |
| 10 | feature | Complaint reasons in info windows | Players had to guess why tenants left | 5.7 |
| 11 | feature | Recycling rules: 2 floors, touching, fills and empties daily | Missing from the first plan | 7.6 |
| 12 | feature | Parking ramp column and chained spaces | Missing from the first plan | 7.7 |
| 13 | feature | Metro footprint B8-B10 and keep B10 clear | Avoid the original's dead-end | 11.3 |
| 14 | feature | Weekend wedding finale | The top rank needs it | 11.5 |
| 15 | feature | Rain and seasonal fly-past events | Missing from the first plan | 9.6, 9.7 |
| 16 | design | Don't replicate bugs: double funds, office escalators; starting funds becomes a setting | Faithful to intent, not to bugs | 2.8, 8.4 |
| 17 | design | Lowest-rent exploit and rent-toggle reset: replicate, then review in M12 | Known balance holes | 5.3 |
| 18 | design | Hotel guests in population after 3 stars | Unverified claim | 7.9 |
| 19 | test | Balance runs replay the guides' strategies (offices-only, condos-first) | Checks the climb feels like the original | 11.7 |
| 20 | process | `gameplay-expert` reviews each gameplay issue before `ready` | Faithful replication | 0.7 |
| 21 | feature | Our own cheats (debug money, unlock all, instant build), kept apart from normal play | Owner wants them; the original's bug cheats are not replicated | M12+ |
