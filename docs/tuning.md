# Tuning: the knobs that make the game easier or harder

Every value lives in `scripts/sim/` as a named `const`, so changing one is a one-line edit plus the
pinned-hash tests it moves. Values were read from the code on 2026-11-24. **Easier** says which way
to turn the knob to make the game easier. This list feeds difficulty settings (#380): a preset would set a group
of these together. "Ref" means the value comes from the reference; anything else is our own guess.

## Money

| Knob | File | Now | Easier | Notes |
|---|---|---|---|---|
| Starting funds | `ledger.gd` DEFAULT_STARTING_FUNDS | $2,000,000 | Up | Already a new-game setting |
| Fire rescue cost | `fire.gd` RESCUE_COST / _WITH_PAD | $500,000 / $300,000 | Down | Ref (owner ruling) |
| Ransom | `threat.gd` PAY_COST | $200,000 | Down | Ref (owner ruling) |
| Repair cost | `fire.gd` REPAIR_PERCENT | 50% of build cost | Down | Owner ruling #373 |
| Plumber | `pipe.gd` PLUMBER_COST | $25,000 | Down | Ours |
| Festival sponsor | `festival.gd` SPONSOR_COST | $50,000 | Down | Ours |

## Tenants, grades and mood

| Knob | File | Now | Easier | Notes |
|---|---|---|---|---|
| Grade bands | `grades.gd` B_FROM (A over 200) | B 150, A 200 | Down | Ref (plan 5.1) |
| Rent stress | `rent.gd` level offsets | -30 / -15 / 0 / +30 | Smaller penalty | Ref |
| Office leaves after C days | `evaluation.gd` OFFICE_RED_DAYS | 2 | Up | Ref |
| Condo leaves on C | `evaluation.gd` CONDO_LEAVE_PERCENT | 100% | Down | Ref |
| Friends fill vacancies (A rooms) | `evaluation.gd` FRIEND_PERCENT / FRIEND_REACH | 100% / 12 cols | Up | Ref |
| Mood change per day | `mood.gd` STEP | 8 | Up (faster recovery) | Ours |
| Low mood line / days to notice | `mood.gd` LOW_BELOW / LEAVE_DAYS | 35 / 5 | Down / up | Ours |
| Fire / threat mood shock | `mood.gd` FIRE_SHOCK / THREAT_SHOCK | 25 / 15 | Down | Ours |
| Noise: complaint line, stress per level | `complaints.gd` NOISE_FROM, `noise.gd` STRESS_PER_NOISE_LEVEL | 3 / 5 | Up / down (0 turns it off) | Ours |
| Word of mouth: stress per C neighbour | `word_of_mouth.gd` STRESS_PER_COMPLAINER | 8 | Down | Ours |
| Stress shown as uneasy / angry | `people.gd` UNEASY_FROM / ANGRY_OVER | 80 / 120 | Up | Display only |

## Stars and the top rank

| Knob | File | Now | Easier | Notes |
|---|---|---|---|---|
| Population per star | `star_rules.gd` REQUIREMENTS | 300 / 1,000 / 5,000 / 10,000 | Down | Ref |
| Top rank population | `star_rules.gd` TOP_RANK | 15,000 | Down | Ref |
| VIP good verdict line | `vip.gd` GOOD_FROM | 150 | Down | Ref (B line) |
| VIP retry after a bad verdict | `vip.gd` RETRY_DAYS | 3 days | Down | Ours |
| Wedding guests needed | `wedding.gd` MIN_GUESTS / GUESTS / CROWD_LIMIT | 20 of 40, lobby queue under 30 | Fewer / higher | Ours |
| Offices per medical centre | `demands.gd` OFFICES_PER_MEDICAL | 20 | Up | Owner ruling #170 |

## Events

| Knob | File | Now | Easier | Notes |
|---|---|---|---|---|
| Fire chance | `fire.gd` CHANCE | about 4% a day | Down | Ours |
| Fire spread | `fire.gd` SPREAD_PERCENT | 35% a period | Down | Ours |
| Threat chance | `threat.gd` CHANCE | about 3% a day | Down | Ours |
| Stuck elevator | `stall.gd` ARM_ONE_IN | about 1 day in 8 | Up | Ours |
| Street festival | `festival.gd` ONE_IN / YEARLY_CAP | 1 in 4 weekends, 1 a year | n/a | Mostly an upside |
| Open event cap | `events.gd` MAX_OPEN | 3 | Down | Ours |

## Hotel, cleaning and services

| Knob | File | Now | Easier | Notes |
|---|---|---|---|---|
| Booking chance | `hotel.gd` BOOK_PERCENT | 70% a night | Up | Ours |
| Guest patience | `hotel.gd` PATIENCE_MINUTES | 90 | Up | Ours |
| Days dirty before pests | `pests.gd` INFEST_DAYS | 3 | Up | Owner-accepted guess |
| Clean time per room | `housekeeping.gd` CLEAN_MINUTES | 30 | Down | Ours |
| Recycling capacity | `recycling.gd` CAPACITY | 18,000 | Up | Ours |
| Guards per security office | `security.gd` GUARDS_PER_OFFICE | 4 | Up | Ours |

## Transport

| Knob | File | Now | Easier | Notes |
|---|---|---|---|---|
| Car capacity | `cars.gd` / catalogue | local 17, express 36 | Up | Ref (owner ruling) |
| Idle car returns home after | `cars.gd` IDLE_DWELL | 2 sim minutes | Down | Ours |
| Arrival spread | `people.gd` ARRIVAL_SPREAD | 0 to 15 minutes late | Up (flatter rush) | Ours |

## Presets

Difficulty (#380) is Easy, Normal or Hard, picked in Settings, New game and fixed when a tower is built (the Settings
panel shows the running tower's preset read-only). It is saved with the tower; saves from before it load as Normal. The
table is `scripts/sim/difficulty.gd`: integer percent multipliers applied where the knob is read, as `value * pct / 100`.
Normal is all 100, so it is exactly the game above.

| Knob group | Easy | Normal | Hard | Applied to |
|---|---|---|---|---|
| Starting funds | 150% | 100% | 75% | the new-game funds setting |
| Rent and hotel income | 120% | 100% | 90% | `Ledger.income`, `Ledger.hotel` |
| Event chances | 50% | 100% | 150% | fire, threat, stuck elevator (the elevator's odds are `ARM_ONE_IN * 100 / pct`) |
| Event costs | 50% | 100% | 125% | fire rescue, ransom, repair, plumber, elevator crew |
| Mood change per day | 125% | 100% | 75% | `Mood.STEP` (the low-mood line is not scaled) |

Never scaled, under any preset: star population thresholds, the top rank, unlock order, structural rules, the clock. A
test asserts the star thresholds are identical under every preset. All the percentages are our own guesses.
