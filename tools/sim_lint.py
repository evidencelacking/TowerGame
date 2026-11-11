"""Bans engine features that would make the simulation differ between machines.

Applies to every .gd file under scripts/sim/. The simulation uses integers only, a seeded
generator of its own, and a fixed tick.
"""
import re
from pathlib import Path

BANNED = {
    "floating point": r"\bfloat\b|\b\d+\.\d+|\b\d+[eE][-+]?\d+\b|\b(Vector2|Vector3|Rect2|Transform2D|PI|TAU|INF|NAN)\b"
    r"|\b(sqrt|sin|cos|tan|atan2?|pow|lerp|fmod|snappedf|floorf|ceilf|roundf|randfn)\b",
    "randomness": r"\b(randf|randi|randf_range|randi_range|randomize|rand_from_seed|RandomNumberGenerator|pick_random|shuffle)\b",
    "wall clock": r"\b(Time\.|OS\.get_ticks|OS\.get_unix)",
    "async timing": r"\b(await|Timer|create_tween|Tween)\b",
    "physics or navigation": r"\b(CharacterBody[23]D|RigidBody[23]D|Area[23]D|NavigationAgent[23]D|NavigationServer[23]D|PhysicsServer[23]D)\b",
    "scene tree": r"\b(get_tree|get_node)\b|\$[A-Za-z\"]",
    "engine delta": r"\bdelta\b",
}
COMPILED = {name: re.compile(pattern) for name, pattern in BANNED.items()}
STRING = re.compile(r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'")


def find_violations(text):
    """Returns (line number, rule) pairs, ignoring comments and string contents."""
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        code = STRING.sub('""', line).split("#", 1)[0]
        found += [(number, name) for name, pattern in COMPILED.items() if pattern.search(code)]
    return found


def lint_simulation(root):
    problems = []
    for path in sorted((Path(root) / "scripts" / "sim").rglob("*.gd")):
        for number, rule in find_violations(path.read_text(encoding="utf-8")):
            problems.append(f"{path.name}:{number}: {rule} is not allowed in the simulation")
    return problems


if __name__ == "__main__":
    import sys

    found = lint_simulation(Path(__file__).resolve().parent.parent)
    print("\n".join(found))
    sys.exit(1 if found else 0)
