# Gameplay reference: the original game's rules

The knowledge base for the `gameplay-expert` agent and the baseline we replicate. Written in
our own words; no text or images are copied from the sources.

## Sources and how much to trust them

Local copies are in `D:\Claude\Tower Game\references\` (git-ignored, never committed).

| Tag | Source | Trust |
|---|---|---|
| M | User's manual, 1994 (printed page numbers) | Highest. The manual itself says its "Inside the simulation" numbers are illustrative, not the real formulas |
| K | Player FAQ, 2004-05 (finished the game twice) | High for walkthrough facts, notes its own doubts |
| F | Player FAQ, 2006-07 | Medium; some numbers differ from M |
| I | Player guide, 2000 | Medium; short |
| S | Player guide, 2003-04 | Medium; some claims marked unconfirmed by its author |
| W | StrategyWiki overview page (subpages are empty) | Overview only |
| V | Player video guide (one full run to the top rank; captions turned into text, 2026) | Medium-high for on-screen costs, caps and unlocks; medium for mechanics, where it hedges; the author plays at top rent |

**Rule for conflicts (owner, 2026-11-10):** M wins, unless two or more player sources agree
with each other on a different value; then they win. Where M is silent, use a value two player
sources agree on. Anything else is *unverified*: we pick a value, label it, and tune it by play.

## Owner decisions

| Date | Decision |
|---|---|
| 2026-11-10 | Two passenger elevator types: **local** (standard, 17 per car) and **express** (larger, 36 per car). Guide figures of 21, 30 and 42 are set aside |
| 2026-11-10 | Resolved values: one transfer per trip; at most 7 escalators a trip; fire rescue $500,000 and treasure $500,000 (players agree); ransom $200,000 (M) |
| 2026-11-10 | We add our own cheats later (M12+); the original's bugs are not replicated |
| 2026-11-10 | Graphics start as native Godot shapes so the game is playable first; original art comes in M10. No art or animation from the original game is used |
| 2026-11-11 | Office hours are tunable constants, starting at arrive 9:00, break 10:30, lunch 12:00, leave 17:00 (#67) |
| 2026-11-11 | Condo price set before transport (V): fixed for now. A condo cannot sell until people can reach it; may be revisited |

## Time

- A day has 6 periods; the clock runs fast at night and slow at rush hours (M p26).
- A week is 2 weekdays (WD) and 1 weekend day (WE); each week is a quarter; 4 quarters a year,
  so a year is 12 days (M, F). A game starts at 5:00 on 1st WD, 1Q, year 1 (F).
- The manual's simulation model uses 300 frames a period as an illustration, not a real tick
  count (M p62). Our ticks per period are our own constants, unverified and tunable (owner, #2).
- Offices are empty on weekends; shops and food do most weekend trade (K, I).
- Office rent arrives at the start of each quarter, on the 1st WD (K, S). V puts the renewal
  at 5:00 that day (*unverified*; V hedges).
- Condos do not sell between 21:00 and 7:00; offices lease only until 13:00 on weekdays (V).
- Some events happen only on the 1st WD or only on the weekend (F). Known: rent on the 1st WD
  (K, S); the wedding and the weekend shop and food trade on WE (M p28, W, K, I). Any other
  WD1-only events are unverified.

## Money

- Starting funds $2,000,000 (K). Bulldozing is free (M p48).
- Every room also pays for the floor beneath it, $500 per unit (M p47, K).
- Running costs are charged per quarter: elevators (about $10,000 a quarter each, K),
  security, housekeeping, recycling, parking ramps, escalators, lobbies. Stairs have none (K).
- Condos are sold once. If the owners leave or the condo is destroyed, the sale price is
  refunded, even into a negative balance (M p53, p65; F, V).
- Rent is set per unit, not per type (V).

## Star ratings

| Rank | Requirement (agreed by K, F, S, I unless noted) |
|---|---|
| 1 | Start |
| 2 | Population 300 (V agrees; S says 250) |
| 3 | Population 1,000 and a security office (I says two; K corrected itself to one) |
| 4 | Population 5,000, recycling and medical demand met, more than one hotel suite (K), a good VIP visit |
| 5 | Population 10,000 and a metro station |
| Top rank | 5 stars, population 15,000, a cathedral on floor 100, and a wedding there on a weekend (M p28, W) |

- Population counts people currently in the tower, so hotels swell it at night (W).
- *Unverified* (K): hotel guests count toward 3 stars but no longer once there.
- The VIP may be unhappy; another VIP comes later (K, F).

## Construction and placement

| Item | Cost | Unlock | Removable | Size and placement |
|---|---|---|---|---|
| Lobby | $5,000 per unit, plus the $500-per-unit floor under it (I, F, K) | 1 | No | Floor 1, then every 15 floors (15, 30 ... 90). Ground lobby may be 2 or 3 floors tall |
| Floor | $500 per unit | 1 | No | No floor wider than the one below (M p50) |
| Stairs | $5,000 | 1 | Yes | Between two floors; not over elevators |
| Local elevator | $200,000 shaft, $80,000 car | 1 | Yes | Up to 30 floors including basements |
| Office | $40,000 | 1 | Yes | Above ground; 6 workers |
| Condo | $80,000 | 1 | Yes | Above ground; 3 residents |
| Fast food | $100,000 | 1 | Yes | Above or below; 5 kinds (F) |
| Service elevator | $100,000 shaft, $50,000 car | 2 | Yes | Staff only |
| Single hotel room | $20,000 | 2 | Yes | 1 guest |
| Housekeeping | $50,000 | 2 | No (K, S) | 6 staff |
| Security | $100,000 | 2 | No | |
| Escalator | $20,000 | 3 | Yes | Commercial, lobby or empty floor only |
| Express elevator | $400,000 shaft, $150,000 car | 3 | Yes | Any height; stops at lobbies and every basement |
| Twin room | $50,000 | 3 | Yes | 2 guests |
| Suite | $100,000 | 3 | Yes | 2 guests, needs a parking space each |
| Restaurant | $200,000 | 3 | Yes | 5 kinds (F) |
| Retail shop | $100,000 | 3 | Yes | 11 kinds (F) |
| Movie theatre | $500,000 | 3 | No (M p54) | 2 floors; about 14 films (F) |
| Party hall | $100,000 | 3 | Yes | |
| Medical centre | $500,000 | 3 | No (K) | |
| Recycling centre | $500,000 | 3 | Yes | 2 floors, underground, must touch other centres |
| Parking ramp | $50,000 | 3 | Yes | One vertical column under the ground lobby |
| Parking space | $3,000 | 3 | Yes | Must chain to a ramp; broken chains stop working |
| Metro station | $1,000,000 | 4 | No | 3 floors, bottom at B10, nothing below; one per tower |
| Cathedral | $3,000,000 | 5 | No | Floor 100 only; one per tower |

- Limits (I): 24 shafts, 8 cars per shaft, 64 stairs and escalators together, 512 parking
  spaces and shops, 10 medical and security, 16 theatres and party halls, 1 metro,
  1 cathedral. S says 8 security offices; I and V say 10, so 10 wins.
- A 3-floor ground lobby uses up floors 2 and 3, so rooms start on floor 4 (V). Its price
  per floor of height is *unverified*; proposal: the per-unit price once per floor.
- The tower is 100 floors up and 10 down (M p26). There is no floor 0: floor 1 is the ground
  lobby (a 2- or 3-floor lobby is floors 1-2 or 1-3), and basements are B1-B10 (owner, #3, #10).
  Nothing may be wider than the ground lobby.

## Transport

| Way | Rule | Conflicts |
|---|---|---|
| Stairs | At most 4 in a trip (M) | F: capacity 21; V says 3 (M wins) |
| Escalator | No waiting, so always preferred; at most 7 in a trip (M, I) | Decided: 7; V says 6 |
| Local (standard) elevator | 17 per car, 8 cars (M) | Decided: 17 |
| Express elevator | 36 per car (M) | Decided: 36 |
| Service elevator | 17 per car; housekeepers only; must reach recycling (M) | K doubts the recycling rule |
| Emergency stairs | Outside the tower; security only | |

- **Transfers:** people change between elevators only at lobbies, and only once a trip (M).
  S says twice. Sky lobbies are the only transfer points (K, I).
- Two kinds of transport connect only where one lobby touches both, so a sky lobby need only
  span the shafts. Passing a lobby starts a new leg, which resets the stairs and escalator
  counts (V).
- Tenants go down to shops and food, rarely up (V). Housekeepers use service elevators and
  stairs only, mostly going up (V).
- **Order of preference:** escalator, then a waiting elevator, then stairs (M p59, F).
- Above floor 60 you need express elevators (two 30-floor shafts reach only 60) (K).
- **Car controls:** home floor, per-floor stop on/off, and weekday/weekend schedules per
  period: express to top or bottom, response distance, and wait before departure (0 by
  default; players use 30 to 90 seconds to fill cars) (M p40-41, F, S).

## People, stress and grades

- Stress comes from time spent getting somewhere, 0 to 300. Under 80 calm (black), 80-120
  uneasy (pink), over 120 angry (red) (M p62).
- Quality = 300 minus average stress. Over 200 grade A (blue, tenants bring friends),
  150-200 B (yellow, they stay), under 150 C (red, they leave at the next rest period) (M p63).
- Offices leave after a day in the red (M p52).
- Noise: offices disturb hotels and condos, but not each other (K). Disturbance radiates to
  neighbours above, below and beside (M p27).
- Complaints spread by word of mouth (M p61). Complaint messages include "neighbours too noisy",
  "elevator too far" and "conditions are terrible" (rent too high) (K, F, S).
- Rent has 4 levels. At the lowest, tenants effectively never leave (K): the strongest
  known exploit.
- Food and shops are graded by daily customers, not stress. Manual: restaurant A over 25,
  B 18-25, C under 18; shop A over 20, B 15-20, C under 15; daily customers capped at 40
  (restaurant) and 30 (fast food) (M p64-65). F reports daily income tiers by patron count
  (*unverified*).
- Theatre audiences enter at the top floor, leave at the bottom, and shop within 5 floors (M p54, 66).
- Metro visitors shop only underground (M, F).

## Services

- Housekeeping sends one cleaner per floor and covers about 6 floors (K, I). V: 6 cleaners,
  each on a different floor and about 18 rooms a day; without a service elevator most idle.
- Rooms left dirty get pests, which spread along the floor; the only fix is to demolish (M p55, K).
- Recycling fills each day and empties next morning; full centres stop working (K). Centres
  need no transport link, and about 9 serve a full tower (V).
- Medical centres serve office workers (M p56). The cap of 10 counts bulldozed ones (V).
- Parking: office workers demand it from 3 stars; each suite needs a space (M p53, K).
  Office and suite demand can share spaces, as their hours are opposite (V).

## Events

| Event | What happens | Values reported |
|---|---|---|
| Fire | Spreads between rooms and upward; security walks there by emergency stairs, or pay for a helicopter | Rescue $500,000 (K, F, I agree; M says $300,000) |
| Bomb threat | Pay, or security searches floor by floor before 1 pm; a miss destroys about 5 floors | Demand $200,000 (M; K says $300,000) |
| VIP | Stays in a suite; verdict gates the 4th star | |
| Buried treasure | Found while building underground | About $500,000 (K, F agree; M says $200,000) |
| Pests | Dirty hotel rooms | |
| Rain | Fewer visitors, mostly hurts food | |
| Santa | Seasonal fly-past in Q4 at night; no effect | |
| Wedding | At the cathedral on a weekend; awards the top rank | |

Fires and threats only happen once the tower has security (M p58).

## Known quirks, cheats and exploits

| Quirk | Ruling for our game |
|---|---|
| Lobby placed at the bottom-left of a new game doubles funds (K, F, I, S) | A bug. Offer starting funds as a setting instead |
| Ctrl / Ctrl+Shift for a 2- or 3-floor ground lobby | Keep as a normal option |
| Shift-click replaces a room in one step (K) | Keep as a "replace" tool |
| Lowest rent makes tenants stay forever (K) | Replicate first; flag for balance |
| Lower then restore rent clears "conditions are terrible" (F, V) | Exploit; replicate the rule, then fix |
| Escalators in office floors by building before the office (K, V) | Bug; don't replicate |
| Raising a condo's price before it has transport sells it at the higher price (V) | Fix for now: no sale until the condo is reachable (owner, 2026-11-11) |
| Only the first 128 shops and food venues draw their own customers (V) | Bug; owner to decide (conflicts with I's 512 limit) |
| A multi-floor escalator on the ground lobby blocks one directly below (V) | Bug; don't replicate |
| Building on B10 blocks the metro forever (K) | Don't replicate; reserve or warn |
| Leaving the game running overnight earns fortunes (K) | Background and fast-forward play are fine |

## What players found hard (our improvement targets)

- Changing rent room by room ("my arm hurts"), so a bulk rent tool.
- Messages flash past too fast, so a message log.
- Crashes cost progress, so autosave.
- Hidden rules (why tenants leave, permanent rooms, B10) surprise players, so explain them in
  the UI before placement.
- The elevator panel is hard to read, so a clearer panel with a preview.
- The 3-star stage is a wall: the medical, recycling, parking, VIP and suite demands arrive at once.
