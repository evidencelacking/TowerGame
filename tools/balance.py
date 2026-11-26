"""Balance runs (#38): four scripted strategies play 10 game years each on a fixed seed; writes docs/balance.md.

  python tools/balance.py [strategy ...] [years=10] [dry]

Runs tools/balance_run.gd headless under a time limit (the guard denies unbounded script runs). docs/balance.md is
written only by a full run (all four strategies, 10 years, no `dry`). This measures only; nothing here is enforced.
Not part of the test suite.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check import ensure_imported, find_godot, kill_tree  # noqa: E402

TIMEOUT_SECONDS = 7200
STRATEGIES = ["offices", "condos", "hotels", "mixed"]
DOC = ROOT / "docs" / "balance.md"

READING = """## Reading this

- Each row is the state at the end of that game year (12 game days, 30,600 ticks). Funds are dollars; population
  is the permanent population the star rules read.
- The builder (#508) plays like a careful player: a 36-column lobby one floor high, one shaft built to full reach at
  once, rooms placed beside floor that already runs to a shaft (so none is cut off), only a running-cost reserve held
  back, lunch places while they cover under 100 percent of the workers, a service shaft and housekeeping stations for
  hotels, security at 2 stars, and a new wing (lobby plus shaft) only when it can pay for both. It never repairs
  fires, never sets rents, never builds sky lobbies or express shafts. A real player does better, so these numbers
  are floors, not ceilings. Compare strategies against each other more than against the pace target.
- Our own pace target (unverified, ours): 2 stars about year 1, 3 stars by year 2 to 3, 5 stars by year 10 for
  mixed. It is measured here, not enforced.
- Status: ok, stalled (two game years of no building and no growth) or bankrupt (funds below zero; the run stops).
- Same seed, same report: the sim is deterministic and events are on, as in a normal game.
- For the per-quarter money trace, pass `trace` to tools/balance_run.gd (see its header): one TRACE line a quarter
  with build spending, income by kind, upkeep and why building stopped.
"""


FINDINGS = """## Findings (#508; causes below were read from per-quarter money traces, but the knob proposals are unverified guesses)

How much was the builder, how much the sim. The first runs (#38) were mostly the builder:

- Rooms were placed with floor gaps to the shaft, so about half of them were cut off and never filled (the old offices
  run had 20 of 40 rooms cut off in year 1). Fixed: a room goes only beside floor that already runs to a shaft.
- It spent on a second lobby wing and a taller shaft on day 1, held back $150,000 plus $1,000 a room, and built a lunch
  place for every 5 offices (each lost about $15,000 a quarter). Fixed: one full-height shaft, a reserve of one quarter's
  running costs, lunch places only while they cover under 100 percent of the workers.
- Hotels never earned: housekeepers ride service shafts only and the builder had none, so no room was ever cleaned. With
  a service shaft and a station per 90 rooms hotels earn (about $3.9M a quarter at 998 singles in year 10).
- The "stalled with $44M unspent" offices tower was the builder's three-wing, one-shaft box. It now builds up to 11 wings.
- Condos-first went bankrupt in year 2 from the builder's reserve (it stopped building with $150,000 held back while a
  lunch place lost money each quarter), not from early overspending. A pure-condo tower (measured in a trace, not in
  the table) still ends with no income: 107 condos, then funds fall about $20,000 a quarter to bankruptcy in year 4.
  That one is the sim: see the condo knob below. The table's condos-first adds 1 office in 5 and survives.

What is left looks like the sim (proposals for the owner; no number was changed):

| Knob (docs/tuning.md name) | Now | Why it looks off (unverified) | Proposal |
|---|---|---|---|
| Office rent / office cost (`room_catalogue.gd` office rent level 3, cost) | $10,000 a quarter for $44,500 (6 workers) | Payback is about 5 quarters, so a well-played offices tower grows about 1.6 times a year and reaches 3 stars in year 4 against our target of years 2 to 3 | Raise the default rent level or cut the cost by about a quarter; or raise starting funds |
| Starting funds (`ledger.gd`) | $2,000,000 | The lobby, shaft and first car take about $0.5M, leaving about 35 offices | $3,000,000 would speed the start (not run); Easy already gives 150% |
| Condo sale price (`room_catalogue.gd` condo cost, sold at cost in `tenancy.gd`) | $80,000 sale for $80,000 plus $8,000 of floor | A condo loses its floor cost and then pays nothing again, so a condo tower has no income and only the shaft upkeep is left | Sell above cost (for example 110%) or add a small quarterly condo fee |
| Population per star (`star_rules.gd` REQUIREMENTS) | 300 / 1,000 | Ref values; kept. Offices alone reach 5,000 only in year 9 and never get suites or the VIP | Leave as is; tune money instead |
| Hotel people per room (`room_catalogue.gd` hotel_single people 1) and booking chance (`hotel.gd` BOOK_PERCENT) | 1 guest per $20,000 single, 70% | A 998-single hotel holds only about 640 guests: a hotel tower cannot reach 3 stars (1,000 people) in 10 years | Count twin and suite guests more, or raise BOOK_PERCENT; hotels remain the best late-game earner |
| Elevator cars per star (`rooms.gd` CARS_BY_STAR, not in tuning.md) | 2 / 4 / 8 / 8 / 8 | At 1 star a shaft holds only 2 cars of 17, which caps one shaft near 150 to 200 people; the builder answers with a shaft per wing | Add it to tuning.md; consider 3 cars at 1 star |
| Lunch place demand (`demands.gd` FOOD and `commerce.gd` lunch capacity) | demand open under 100% coverage | Each lunch place loses money until it has customers (about $15,000 a quarter when over-built) | Tell the player how many it takes, or open the demand at 60% |

Other measured facts: the offices tower ends year 10 with $82M unspent at 5,286 people and 3 stars because it has
run out of 400-column, 29-floor room, not funds; stars 4 and 5 need suites, the VIP and a metro the builder never
reaches for in that strategy. Mixed ends near 2,380 people with $28M unspent for the same reason.

### Star gate: UI only

The star rank gates the build menu in the view only (`placement_ghost.gd` evaluate: "Needs N stars"; the toolbar
hides locked tools). `Rooms.check_place` and `Rooms.place_room` do not check stars, and the PLACE_ROOM command
(`tower.gd`) calls `place_room` directly, so a queued command can place any room at 1 star. Only cars are gated in the
sim (`Rooms.add_car`, by `CARS_BY_STAR`). The builder here gates itself with `Tower.unlocked_stars`. Not fixed here.
"""


def parse(text):
    """{strategy: {"rows": [[year, funds, people, stars, status]], "notes": [str]}} from the script's output."""
    runs = {}
    for line in text.splitlines():
        parts = line.strip().split("|")
        if parts[0] == "ROW" and len(parts) == 7:
            run = runs.setdefault(parts[1], {"rows": [], "notes": []})
            run["rows"].append([int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), parts[6]])
        elif parts[0] == "NOTE" and len(parts) >= 3:
            runs.setdefault(parts[1], {"rows": [], "notes": []})["notes"].append("|".join(parts[2:]))
    return runs


def first_year_with(rows, stars):
    for year, _funds, _people, got, _status in rows:
        if got >= stars:
            return f"year {year}"
    return "not reached"


def render(runs):
    out = ["# Balance runs", "",
           "Generated by `python tools/balance.py` (#38): four scripted strategies, 10 game years each, seed 42. "
           "Measured only; no sim number was changed.", ""]
    for name in STRATEGIES:
        if name not in runs:
            continue
        run = runs[name]
        out += [f"## {name}", "", "| Year | Funds | Population | Stars | Status |", "|---|---|---|---|---|"]
        for year, funds, people, stars, status in run["rows"]:
            out.append(f"| {year} | ${funds:,} | {people:,} | {stars} | {status} |")
        out.append("")
        for note in run["notes"]:
            out.append(f"- {note}")
        if run["notes"]:
            out.append("")
    out += ["## Pace against our target (unverified, ours)", "",
            "| Strategy | 2 stars | 3 stars | 5 stars |", "|---|---|---|---|"]
    for name in STRATEGIES:
        if name in runs:
            rows = runs[name]["rows"]
            out.append(f"| {name} | {first_year_with(rows, 2)} | {first_year_with(rows, 3)} | {first_year_with(rows, 5)} |")
    out += ["", "Target for mixed: 2 stars about year 1, 3 stars by year 2 to 3, 5 stars by year 10.", "", FINDINGS, READING]
    return "\n".join(out)


def main(args):
    names = [a for a in args if a in STRATEGIES]
    years = [a for a in args if a.startswith("years=")]
    full = not names and not years and "dry" not in args
    godot = find_godot()
    if not godot:
        print("Godot not found. Install it or set the GODOT environment variable.")
        return 1
    problems = ensure_imported(ROOT, godot)
    if problems:
        print("\n".join(problems))
        return 1
    out = ROOT / "balance_output.txt"
    with open(out, "w", encoding="utf-8") as log:
        process = subprocess.Popen(
            [godot, "--headless", "--path", str(ROOT), "--script", "res://tools/balance_run.gd", "--", *years, *names],
            stdout=log, stderr=subprocess.STDOUT,
        )
        try:
            code = process.wait(timeout=TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            kill_tree(process)
            print(f"Timed out after {TIMEOUT_SECONDS} s; partial output in {out}")
            return 1
    text = out.read_text(encoding="utf-8", errors="replace")
    runs = parse(text)
    if code != 0 or "DONE" not in text or not runs:
        print(text[-3000:])
        return code or 1
    out.unlink()
    doc = render(runs)
    print(doc)
    if full:
        DOC.write_text(doc, encoding="utf-8")
        print(f"\nWrote {DOC}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
