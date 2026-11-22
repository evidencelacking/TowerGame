"""Synthesise the few game sounds that have no CC0 recording into assets/sounds/ (#385, #396).

Every other sound in assets/sounds/ is a converted CC0 file listed in assets/sounds/SOURCES.md; this
script never writes those (it skips any name whose SOURCES.md row names a pack).

Standard library only and fully deterministic: every sound draws from its own random.Random seeded
from a fixed seed and the sound's name, so two runs write identical bytes. Nothing here reads or
samples any existing audio; every sound is built from tones, envelopes and filtered noise.
Output is 22050 Hz mono 16-bit. One-shots are under 1.5 s; loops run 2-4 s and end seamlessly
(the tail is crossfaded into the head, and the game loops the whole file).

Usage: python tools/make_sounds.py [output_dir]
"""
import io
import math
import random
import struct
import sys
import wave
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sounds"
RATE = 22050
SEED = 385
TAU = 2 * math.pi


# ---- primitives -------------------------------------------------------------------------------

def silence(sec):
    return [0.0] * int(sec * RATE)


def env(n, attack=0.005, decay=0.0, sustain=1.0, release=0.05):
    """Per-sample gain: linear attack, exponential decay toward sustain, linear release."""
    a, r = max(1, int(attack * RATE)), max(1, int(release * RATE))
    out = []
    for i in range(n):
        if i < a:
            g = i / a
        else:
            t = (i - a) / RATE
            g = sustain + (1 - sustain) * math.exp(-t / decay) if decay > 0 else sustain
        left = n - i
        if left < r:
            g *= left / r
        out.append(g)
    return out


def tone(freq, sec, shape="sine", vol=1.0, glide=None, vibrato=0.0, **adsr):
    """A pitched tone; glide is the end frequency (exponential sweep)."""
    n = int(sec * RATE)
    e = env(n, **adsr)
    out, phase = [], 0.0
    for i in range(n):
        f = freq if glide is None else freq * (glide / freq) ** (i / n)
        if vibrato:
            f *= 1 + 0.01 * math.sin(TAU * vibrato * i / RATE)
        phase += f / RATE
        p = phase % 1.0
        if shape == "sine":
            s = math.sin(TAU * p)
        elif shape == "square":
            s = 1.0 if p < 0.5 else -1.0
        elif shape == "tri":
            s = 4 * abs(p - 0.5) - 1
        elif shape == "saw":
            s = 2 * p - 1
        else:  # soft: sine plus two harmonics
            s = (math.sin(TAU * p) + 0.4 * math.sin(2 * TAU * p) + 0.2 * math.sin(3 * TAU * p)) / 1.6
        out.append(s * e[i] * vol)
    return out


def noise(rng, sec, vol=1.0, low=None, high=None, **adsr):
    """White noise through optional one-pole low-pass (low = cutoff Hz) and high-pass (high = Hz)."""
    n = int(sec * RATE)
    e = env(n, **adsr)
    la = 1 - math.exp(-TAU * low / RATE) if low else 1.0
    ha = math.exp(-TAU * high / RATE) if high else 0.0
    out, lp, hp_in, hp_out = [], 0.0, 0.0, 0.0
    for i in range(n):
        x = rng.uniform(-1, 1)
        lp += la * (x - lp)
        y = lp
        if high:
            hp_out = ha * (hp_out + y - hp_in)
            hp_in = y
            y = hp_out
        out.append(y * e[i] * vol * (1.6 if low else 1.0))
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def place(track, at):
    """Delay a track by `at` seconds."""
    return silence(at) + track


def seq(*notes):
    out = []
    for t in notes:
        out += t
    return out


def loopify(track, sec):
    """Make track (longer than sec by a crossfade tail) loop seamlessly over `sec` seconds."""
    n = int(sec * RATE)
    x = len(track) - n
    assert x > 0
    out = track[:n]
    for i in range(x):
        f = i / x
        out[i] = track[i] * f + track[n + i] * (1 - f)
    return out


def loop_noise(rng, sec, **kw):
    return loopify(noise(rng, sec + 0.4, attack=0.0005, release=0.0005, **kw), sec)


def add_at(track, at_sec, part):
    at = int(at_sec * RATE)
    for i, v in enumerate(part):
        if at + i < len(track):
            track[at + i] += v


# ---- the sounds -------------------------------------------------------------------------------

def thud(freq, sec, vol=0.9):
    return tone(freq, sec, "sine", vol, glide=freq * 0.45, attack=0.002, decay=sec * 0.3, release=sec * 0.4)


def rec_dancehall(rng):
    sec = 2.0   # 5 beats at 150 bpm
    out = silence(sec)
    for k in range(5):
        add_at(out, k * 0.4, thud(60, 0.2, 0.8))
        if k % 2 == 1:
            add_at(out, k * 0.4, noise(rng, 0.1, 0.25, high=3000, attack=0.001, decay=0.03, release=0.04))
    for k, f in enumerate([55, 55, 82]):
        add_at(out, k * 0.65, tone(f, 0.6, "saw", 0.12, attack=0.01, release=0.1))
    return out


RECIPES = {"DanceHall1": rec_dancehall}   # the only generated sound left (#396); every other name is a converted CC0 file
LOOPS = {"DanceHall1"}   # the generated sounds that are loops (2-4 s, seamless); the rest would be one-shots under 1.5 s


def render(name):
    """The 16-bit mono PCM bytes of one sound, scaled down if it would peak above 0.8."""
    rng = random.Random(zlib.crc32(name.encode("utf-8")) ^ SEED)
    samples = RECIPES[name](rng)
    peak = max(max(abs(v) for v in samples), 1e-9)
    scale = 0.8 / peak if peak > 0.8 else 1.0
    return b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v * scale)) * 32767)) for v in samples)


def wav_bytes(name):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(render(name))
    return buf.getvalue()


def sourced_names(out_dir):
    """Names whose SOURCES.md row says they are a CC0 recording (any pack other than "generated")."""
    path = out_dir / "SOURCES.md"
    if not path.exists():
        return set()
    names = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 2 and cells[0].endswith(".wav") and cells[1] != "generated":
            names.add(cells[0][: -len(".wav")])
    return names


def main(argv):
    out_dir = Path(argv[1]) if len(argv) > 1 else OUT
    out_dir.mkdir(parents=True, exist_ok=True)
    skip = sourced_names(out_dir)
    names = [n for n in RECIPES if n not in skip]
    for name in names:
        (out_dir / f"{name}.wav").write_bytes(wav_bytes(name))
    print(f"wrote {len(names)} generated sounds to {out_dir} (left {len(skip)} sourced files alone)")


if __name__ == "__main__":
    main(sys.argv)
