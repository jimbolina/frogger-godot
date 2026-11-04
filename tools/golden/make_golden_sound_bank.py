"""Independent FrogLord Windows header facts, using synthetic metadata only."""
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT


def generate():
    rows = [[1, 0, 22050, 1, 1, 11025, 16], [1, 22050, 44100, 1, 1, 22050, 16], [0, 999999, 0, 1, 1, 11025, 16], [1, 66150, 11025, 1, 1, 11025, 8]]
    facts = []
    for sound_id, row in enumerate(rows):
        present, offset, size, _, _, rate, bits = row
        facts.append(dict(sound_id=sound_id, source_offset=4+28*sound_id, present=present==1, offset=offset, size=size, rate=rate, bits=bits, frames=size//(bits//8)))
    return dict(schema="windows-sound-bank-v1", body_size=77175, rows=rows, facts=facts)


if __name__ == "__main__":
    path = REPO_ROOT / "tests/golden/synthetic/sound_bank.json"
    path.write_text(json.dumps(generate(), indent=2) + "\n")
