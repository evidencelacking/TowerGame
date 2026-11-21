"""Synthesise the game's original sound set into assets/sounds/ (#385).

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


def blips(rng, sec, rate, freq_lo, freq_hi, dur, vol=0.6, shape="sine"):
    """Scatter short tones at random times: birds, chatter, glasses. Loops over `sec`."""
    track = silence(sec + 0.4)
    for _ in range(int(sec * rate)):
        f = rng.uniform(freq_lo, freq_hi)
        b = tone(f, dur, shape, vol * rng.uniform(0.5, 1.0), glide=f * rng.uniform(0.8, 1.3), attack=0.004, release=dur * 0.5)
        add_at(track, rng.uniform(0, sec), b)
    return loopify(track, sec)


def murmur(rng, sec, low, high, rate, vol=0.5, chatter=(180, 420)):
    """Crowd-like bed: band-limited noise with a slow swell plus syllable-like blips."""
    bed = loop_noise(rng, sec, vol=vol, low=low, high=high)
    lfo = round(rng.uniform(0.4, 0.9) * sec) / sec  # whole cycles per loop so the swell stays seamless
    bed = [v * (0.75 + 0.25 * math.sin(TAU * lfo * i / RATE)) for i, v in enumerate(bed)]
    return mix(bed, blips(rng, sec, rate, chatter[0], chatter[1], 0.09, vol * 0.5, "soft"))


def hum(sec, freqs, vol=0.4, wobble=0.0):
    """Sum of sines whose frequencies are whole cycles per loop, so the loop is exact."""
    n = int(sec * RATE)
    fr = [round(f * sec) / sec for f in freqs]
    wb = round(wobble * sec) / sec if wobble else 0.0
    out = []
    for i in range(n):
        v = sum(math.sin(TAU * f * i / RATE) / (1 + k) for k, f in enumerate(fr))
        if wb:
            v *= 1 + 0.1 * math.sin(TAU * wb * i / RATE)
        out.append(v * vol)
    return out


# ---- the sounds -------------------------------------------------------------------------------

def note_seq(freqs, step, shape="tri", vol=0.5, hold=1.6, release=0.08):
    out = [0.0]
    for i, f in enumerate(freqs):
        out = mix(out, place(tone(f, step * hold, shape, vol, attack=0.005, decay=step, release=release), i * step))
    return out


def thud(freq, sec, vol=0.9):
    return tone(freq, sec, "sine", vol, glide=freq * 0.45, attack=0.002, decay=sec * 0.3, release=sec * 0.4)


def rec_build1(rng):
    return mix(thud(120, 0.22), noise(rng, 0.12, 0.3, low=1500, attack=0.001, decay=0.03, release=0.05),
               place(tone(660, 0.12, "tri", 0.3, attack=0.002, release=0.08), 0.05))


def rec_build2(rng):
    return mix(thud(150, 0.2), place(thud(95, 0.25, 0.7), 0.09),
               noise(rng, 0.1, 0.3, low=2500, attack=0.001, decay=0.03, release=0.04))


def rec_buy(rng):
    ching = mix(tone(1568, 0.5, "sine", 0.5, attack=0.001, decay=0.12, release=0.2),
                tone(2349, 0.5, "sine", 0.35, attack=0.001, decay=0.1, release=0.2),
                tone(3136, 0.3, "sine", 0.2, attack=0.001, decay=0.06, release=0.1))
    return mix(noise(rng, 0.06, 0.4, high=3000, attack=0.001, release=0.03),
               place(thud(300, 0.08, 0.4), 0.02), place(ching, 0.1))


def rec_demolish(rng):
    out = noise(rng, 1.1, 0.8, low=900, attack=0.01, decay=0.4, release=0.5)
    for _ in range(7):
        out = mix(out, place(noise(rng, 0.08, 0.5, low=rng.uniform(600, 2400), attack=0.001, decay=0.02, release=0.04),
                             rng.uniform(0.05, 0.8)))
    return mix(out, thud(70, 0.5, 0.9))


def rec_doorbell(rng):
    return mix(tone(784, 0.6, "sine", 0.5, attack=0.002, decay=0.25, release=0.2),
               place(tone(622, 0.8, "sine", 0.5, attack=0.002, decay=0.35, release=0.3), 0.35))


def rec_dunno(rng):
    return mix(tone(330, 0.3, "tri", 0.5, glide=250, attack=0.01, release=0.1),
               place(tone(280, 0.4, "tri", 0.5, glide=200, attack=0.01, release=0.15), 0.28))


def rec_noplop(rng):
    return tone(200, 0.18, "square", 0.3, glide=110, attack=0.002, decay=0.1, release=0.06)


def rec_elevator_move(rng):
    return mix(hum(2.0, [55, 110, 165], 0.5, wobble=1.0), loop_noise(rng, 2.0, vol=0.08, low=300))


def rec_elevator_open1(rng):
    return mix(tone(880, 0.7, "sine", 0.5, attack=0.002, decay=0.3, release=0.2),
               place(tone(1175, 0.8, "sine", 0.5, attack=0.002, decay=0.3, release=0.3), 0.25))


def rec_elevator_open2(rng):
    return mix(tone(1047, 0.7, "sine", 0.5, attack=0.002, decay=0.3, release=0.2),
               place(tone(784, 0.8, "sine", 0.5, attack=0.002, decay=0.3, release=0.3), 0.25))


def rec_explode(rng):
    return mix(noise(rng, 1.0, 1.0, low=700, attack=0.002, decay=0.45, release=0.6),
               thud(55, 0.8, 1.0), noise(rng, 0.3, 0.5, low=4000, attack=0.001, decay=0.05, release=0.2))


def rec_fire(rng):
    sec = 2.0
    out = loop_noise(rng, sec, vol=0.18, low=500)
    for _ in range(40):
        add_at(out, rng.uniform(0, sec - 0.1),
               noise(rng, 0.03, rng.uniform(0.3, 0.9), high=1500, attack=0.0005, decay=0.006, release=0.01))
    return out


def rec_firetruck(rng):
    def beep(f):
        return tone(f, 0.35, "square", 0.25, attack=0.02, release=0.05)
    return seq(beep(660), beep(880), beep(660))


def rec_helicopter(rng):
    out = silence(1.0)
    for k in range(int(1.0 * 12)):
        add_at(out, k / 12, noise(rng, 0.05, 0.9, low=400, attack=0.002, decay=0.02, release=0.02))
    return mix(out, tone(90, 1.0, "saw", 0.12, attack=0.1, release=0.2))


def rec_intro(rng):
    return mix(note_seq([523, 659, 784, 1047, 784, 1047, 1319], 0.17, "tri", 0.45),
               tone(262, 1.2, "sine", 0.35, attack=0.02, decay=0.5, release=0.3))


def rec_recycling(rng):
    return mix(tone(500, 0.25, "tri", 0.4, glide=900, attack=0.01, release=0.08),
               place(tone(900, 0.25, "tri", 0.4, glide=500, attack=0.01, release=0.1), 0.2),
               noise(rng, 0.4, 0.15, low=2000, attack=0.05, release=0.1))


def rec_santa(rng):
    return note_seq([1319, 1568, 1319, 1568, 1976, 1568, 1319], 0.14, "sine", 0.4, hold=2.5, release=0.1)


def rec_stargot(rng):
    return mix(note_seq([523, 659, 784, 1047], 0.13, "tri", 0.45),
               place(mix(tone(1047, 0.7, "tri", 0.4, attack=0.01, decay=0.3, release=0.3),
                         tone(1319, 0.7, "tri", 0.3, attack=0.01, decay=0.3, release=0.3),
                         tone(1568, 0.7, "sine", 0.3, attack=0.01, decay=0.3, release=0.3)), 0.5))


def rec_terror_hello(rng):
    return mix(tone(110, 0.9, "saw", 0.3, vibrato=6, attack=0.05, release=0.3),
               tone(116, 0.9, "saw", 0.3, vibrato=5, attack=0.05, release=0.3))


def rec_terror_ty(rng):
    return mix(tone(196, 0.5, "soft", 0.4, glide=262, attack=0.02, release=0.15),
               place(tone(262, 0.5, "soft", 0.4, attack=0.02, release=0.2), 0.3))


def rec_wedding(rng):
    return note_seq([392, 523, 659, 784, 659, 784, 1047], 0.18, "sine", 0.4, hold=2.0)


def rec_yay(rng):
    return mix(note_seq([392, 523, 659, 784], 0.1, "tri", 0.45),
               place(noise(rng, 0.5, 0.18, high=2000, low=7000, attack=0.05, release=0.3), 0.25))


def rec_belltoll(rng):
    parts = [(220, 0.6), (440, 0.4), (554, 0.3), (660, 0.25), (880, 0.2)]
    return mix(*[tone(f * 1.003 ** k, 1.2, "sine", v, attack=0.001, decay=0.5 / (1 + k * 0.4), release=0.4)
                 for k, (f, v) in enumerate(parts)])


def rec_rain(rng):
    return mix(loop_noise(rng, 2.0, vol=0.35, low=6000, high=800), loop_noise(rng, 2.0, vol=0.1, low=300))


def rec_thunder(rng):
    return mix(noise(rng, 1.0, 0.9, low=200, attack=0.15, decay=0.5, release=0.6), thud(45, 0.9, 0.8))


def rec_clocktick(rng):
    out = silence(0.6)
    for k in range(2):
        add_at(out, k * 0.25, tone(1800 if k % 2 == 0 else 1500, 0.02, "square", 0.3, attack=0.0005, decay=0.005, release=0.01))
    return out


def theater_clip(index):
    """Fifteen short scene ambiences (a swell, rumble, sting or laughter-like bursts), varied by index."""
    def rec(rng):
        kind = index % 5
        if kind == 0:   # applause-like crackle
            return noise(rng, 0.6, 0.5, high=1200, low=6000, attack=0.2, decay=0.6, release=0.4)
        if kind == 1:   # low rumble
            return mix(noise(rng, 0.6, 0.5, low=250, attack=0.3, release=0.5),
                       tone(55 + index * 3, 0.6, "sine", 0.3, attack=0.3, release=0.5))
        if kind == 2:   # string-like swell
            f = 220 * 2 ** (index / 12)
            return mix(tone(f, 0.6, "saw", 0.12, vibrato=5, attack=0.4, release=0.5),
                       tone(f * 1.5, 0.6, "saw", 0.08, vibrato=5, attack=0.4, release=0.5))
        if kind == 3:   # laughter-like bursts
            out = silence(0.6)
            for k in range(3):
                add_at(out, 0.05 + k * 0.14,
                       tone(rng.uniform(250, 380), 0.12, "soft", 0.5, glide=rng.uniform(200, 300), attack=0.005, release=0.06))
            return out
        return mix(note_seq([330 + index * 5, 392 + index * 5, 330 + index * 5], 0.15, "sine", 0.3, hold=1.5),
                   noise(rng, 0.6, 0.05, low=900, attack=0.1, release=0.3))
    return rec


def rec_bird(variant):
    def rec(rng):
        lo = 2200 + variant * 450
        return blips(rng, 2.0, 2.5 + variant * 0.7, lo, lo + 1500, 0.07 + 0.02 * variant, 0.35)
    return rec


def rec_cricket(rng):
    sec = 2.0
    track = silence(sec + 0.4)
    for k in range(int(sec * 5)):
        for j in range(3):
            add_at(track, k / 5 + j * 0.06, tone(4300, 0.035, "sine", 0.28, attack=0.004, release=0.012))
    return loopify(track, sec)


def rec_crowd(variant):
    def rec(rng):
        return murmur(rng, 2.0, 900 + variant * 300, 150, 7 + variant * 2, 0.5)
    return rec


def rec_office(rng):
    sec = 2.0
    out = murmur(rng, sec, 1200, 200, 2.0, 0.18, (200, 300))
    for _ in range(5):
        add_at(out, rng.uniform(0, sec - 0.1), noise(rng, 0.02, 0.25, high=2500, attack=0.0005, release=0.01))
    return mix(out, hum(sec, [120, 240], 0.05))


def rec_restaurant(variant):
    def rec(rng):
        sec = 2.0
        out = murmur(rng, sec, 1500 + variant * 400, 180, 5 + variant, 0.3 - 0.04 * variant, (200, 380))
        for _ in range(4 + variant):
            add_at(out, rng.uniform(0, sec - 0.4), tone(rng.uniform(2400, 3600), 0.3, "sine", 0.12, attack=0.001, decay=0.06, release=0.1))
        return out
    return rec


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


def rec_subway(variant):
    def rec(rng):
        return mix(loop_noise(rng, 2.0, vol=0.4, low=500 + variant * 250),
                   hum(2.0, [40 + variant * 12, 80 + variant * 20], 0.25, wobble=2 + variant))
    return rec


def rec_vacuum(rng):
    return mix(loop_noise(rng, 2.0, vol=0.3, low=3500, high=300), hum(2.0, [140, 280], 0.12))


def rec_car(variant):
    def rec(rng):
        sec = 2.0
        track = noise(rng, sec + 0.4, 0.2, low=700 + variant * 300, attack=0.0005, release=0.0005)
        for k in range(2):
            add_at(track, k * 1.0 + variant * 0.2, noise(rng, 0.9, 0.4, low=1200 + variant * 400, attack=0.3, release=0.4))
        return loopify(track, sec)
    return rec


def make_recipes():
    r = {
        "Belltoll": rec_belltoll, "Build1": rec_build1, "Build2": rec_build2, "Buy": rec_buy, "Demolish": rec_demolish,
        "Doorbell1": rec_doorbell, "Dunno": rec_dunno, "NoPlop": rec_noplop, "ElevatorMove": rec_elevator_move,
        "ElevatorOpen1": rec_elevator_open1, "ElevatorOpen2": rec_elevator_open2, "Explode1": rec_explode,
        "Fire": rec_fire, "FireTruck1": rec_firetruck, "Helicopter": rec_helicopter, "Intro": rec_intro,
        "Recycling": rec_recycling, "Santa!": rec_santa, "StarGet": rec_stargot, "TerroristHello": rec_terror_hello,
        "TerroristTY": rec_terror_ty, "Wedding": rec_wedding, "Yay1": rec_yay,
        "Rain": rec_rain, "Thunder": rec_thunder, "Cricket1": rec_cricket, "Office1": rec_office,
        "DanceHall1": rec_dancehall, "Vacuum1": rec_vacuum, "ClockTick": rec_clocktick,
    }
    for i in range(1, 5):
        r[f"Bird{i}"] = rec_bird(i - 1)
    for i in range(1, 3):
        r[f"Crowd{i}"] = rec_crowd(i - 1)
        r[f"Subway{i}"] = rec_subway(i - 1)
        r[f"Car{i}"] = rec_car(i - 1)
    for i in range(1, 4):
        r[f"Resturant{i}"] = rec_restaurant(i - 1)
    for i in range(1, 16):
        r[f"Theater{i}"] = theater_clip(i)
    return r


RECIPES = make_recipes()
# The sounds the game plays as loops (2-4 s, seamless); every other sound is a one-shot under 1.5 s.
LOOPS = {"ElevatorMove", "Fire", "Rain", "Cricket1", "Office1", "DanceHall1", "Vacuum1",
         "Bird1", "Bird2", "Bird3", "Bird4", "Crowd1", "Crowd2", "Subway1", "Subway2", "Car1", "Car2",
         "Resturant1", "Resturant2", "Resturant3"}


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


def write_sources(out_dir, names):
    lines = ["# Sound sources", "",
             "Every file here is original, synthesised from tones, envelopes and filtered noise.",
             "Regenerate with `python tools/make_sounds.py`. No existing audio is read or sampled.", "",
             "| File | Source | Licence |", "|---|---|---|"]
    lines += [f"| {n}.wav | generated by tools/make_sounds.py | original, same licence as the repo |" for n in sorted(names)]
    (out_dir / "SOURCES.md").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def main(argv):
    out_dir = Path(argv[1]) if len(argv) > 1 else OUT
    out_dir.mkdir(parents=True, exist_ok=True)
    for name in RECIPES:
        (out_dir / f"{name}.wav").write_bytes(wav_bytes(name))
    write_sources(out_dir, RECIPES)
    print(f"wrote {len(RECIPES)} sounds to {out_dir}")


if __name__ == "__main__":
    main(sys.argv)
