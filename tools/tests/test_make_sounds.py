import re
import struct
import sys
import tempfile
import unittest
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path[:0] = [str(ROOT / "tools")]

import make_sounds  # noqa: E402

CATALOG = (ROOT / "scripts" / "view" / "sound" / "sound_catalog.gd").read_text(encoding="utf-8")


def catalog_names():
    names = []
    for block in ("AMBIENCE_NAMES", "EVENT_NAMES"):
        body = re.search(block + r": Array\[String\] = \[(.*?)\n\]", CATALOG, re.S).group(1)
        names += re.findall(r'"([^"]+)"', body)
    return names


SOUNDS = ROOT / "assets" / "sounds"


def sources_rows():
    """File name -> list of the other cells of its SOURCES.md table row."""
    rows = {}
    for line in (SOUNDS / "SOURCES.md").read_text(encoding="utf-8").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells and cells[0].endswith(".wav"):
            rows[cells[0]] = cells[1:]
    return rows


def read_wav(path):
    with wave.open(str(path)) as w:
        fmt = (w.getnchannels(), w.getsampwidth(), w.getframerate())
        pcm = w.readframes(w.getnframes())
    return fmt, struct.unpack("<%dh" % (len(pcm) // 2), pcm)


class MakeSounds(unittest.TestCase):
    def test_recipes_are_catalog_names_and_loops_are_recipes(self):
        names = catalog_names()
        self.assertEqual(len(names), 58)
        self.assertEqual([n for n in make_sounds.RECIPES if n not in names], [])
        self.assertTrue(make_sounds.LOOPS <= set(make_sounds.RECIPES))

    def test_output_is_deterministic(self):
        for name in make_sounds.RECIPES:
            self.assertEqual(make_sounds.wav_bytes(name), make_sounds.wav_bytes(name), name)

    def test_main_writes_only_generated_names_and_skips_sourced_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            rows = ["| File | Pack | Original file | URL | Licence |", "|---|---|---|---|---|",
                    "| Rain.wav | Kenney Test | x.ogg | https://example.test | CC0 1.0 |",
                    "| DanceHall1.wav | generated | tools/make_sounds.py | - | original |"]
            (tmp / "SOURCES.md").write_text(chr(10).join(rows), encoding="utf-8")
            (tmp / "Rain.wav").write_bytes(b"sourced")
            make_sounds.main(["make_sounds.py", str(tmp)])
            self.assertEqual((tmp / "Rain.wav").read_bytes(), b"sourced")
            written = sorted(p.stem for p in tmp.glob("*.wav") if p.stem != "Rain")
            self.assertEqual(written, sorted(set(make_sounds.RECIPES)))
            self.assertEqual((tmp / "DanceHall1.wav").read_bytes(), make_sounds.wav_bytes("DanceHall1"))

    def test_generated_files_match_the_script(self):
        for name, cells in sources_rows().items():
            if cells[0] == "generated":
                self.assertEqual((SOUNDS / name).read_bytes(), make_sounds.wav_bytes(name[:-4]), name)

    def test_generated_rows_are_exactly_the_recipes(self):
        generated = sorted(n[:-4] for n, c in sources_rows().items() if c[0] == "generated")
        self.assertEqual(generated, sorted(make_sounds.RECIPES))


class ShippedSounds(unittest.TestCase):
    def test_every_wav_has_a_sources_entry_with_a_licence(self):
        rows = sources_rows()
        files = sorted(p.name for p in SOUNDS.glob("*.wav"))
        self.assertEqual(files, sorted(f"{n}.wav" for n in catalog_names()))
        for name in files:
            self.assertIn(name, rows, f"{name} has no SOURCES.md row")
            pack, original, url, licence = rows[name]
            self.assertTrue(pack and original and url and licence, name)
            if pack != "generated":
                self.assertEqual(licence, "CC0 1.0", name)
                self.assertTrue(url.startswith(("https://kenney.nl/assets/", "https://bigsoundbank.com/")), name)
        self.assertEqual(sorted(rows), files, "SOURCES.md lists a file that is not there")

    def test_format_length_loudness_and_size(self):
        total = 0
        for name in catalog_names():
            path = SOUNDS / f"{name}.wav"
            total += path.stat().st_size
            fmt, s = read_wav(path)
            self.assertEqual(fmt, (1, 2, 22050), name)
            sec = len(s) / 22050
            if sec >= 1.5:
                self.assertTrue(2.0 <= sec <= 4.0, f"{name} is {sec}s: neither a one-shot nor a loop")
            else:
                self.assertGreater(sec, 0.01, name)
            peak = max(abs(v) for v in s) / 32768
            self.assertTrue(0.1 < peak <= 0.95, f"{name} peak {peak}")
        self.assertLess(total, 5_000_000)

    def test_loops_join_without_a_click(self):
        # The jump from the last sample back to the first must be no bigger than the largest step
        # already inside the file, otherwise the loop point would be audible as a click.
        loops = [p for p in SOUNDS.glob("*.wav") if len(read_wav(p)[1]) / 22050 >= 2.0]
        self.assertGreaterEqual(len(loops), 20)
        for path in loops:
            s = read_wav(path)[1]
            biggest = max(abs(b - a) for a, b in zip(s, s[1:]))
            self.assertLessEqual(abs(s[0] - s[-1]), biggest, path.name)


if __name__ == "__main__":
    unittest.main()
