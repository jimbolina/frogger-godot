"""Identity-pinned static timing audit. Print scalar facts, never retail excerpts."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

RETAIL_SHA256 = "215b444ebb6317c136cfaded17922909b743deb34ab16f72e140a99d87340e06"
COUNTERS = {"timer_callbacks": 0x475918, "logic_budget": 0x47591C,
            "global_logic_frames": 0x475920}


def verify_identity(path: Path) -> str:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != RETAIL_SHA256:
        raise ValueError("Unsupported executable SHA-256: " + digest)
    return digest


def audit(path: Path, objdump: str) -> dict:
    digest = verify_identity(path)
    result = subprocess.run([objdump, "-d", str(path)], check=True,
                            capture_output=True, text=True)
    instructions = {}
    for line in result.stdout.splitlines():
        match = re.match(r"\s*([0-9a-f]+):\s+(?:[0-9a-f]{2}\s+)+\s*([^\t]+.*)$", line)
        if match:
            operation = match[2].split()[0]
            numeric_operands = tuple(int(value, 16) for value in re.findall(r"0x([0-9a-f]+)", match[2]))
            instructions[int(match[1], 16)] = (operation, numeric_operands)
    checks = {0x4234EB: ("push", (20,)), 0x4234E6: ("push", (0x4238C0,)),
              0x4234ED: ("call", (0x457B50,)), 0x457B8D: ("call", (0x4AD5BC,)),
              0x4238E1: ("incl", (0x475918,)), 0x4238ED: ("test", (1,)),
              0x4238F0: ("je", (0x4238F8,)), 0x4238F2: ("incl", (0x47591C,)),
              0x4312BD: ("mov", (0x47591C,)), 0x4312F0: ("mov", (2,)),
              0x4312F5: ("call", (0x4310D0,)), 0x4310DF: ("mov", (0x475920,)),
              0x4310EA: ("inc", ()), 0x4310ED: ("mov", (0x475920,))}
    for address, expected in checks.items():
        if instructions.get(address) != expected:
            raise ValueError(f"Static timing assertion failed at {address:#010x}")
    return {"sha256": digest, "image_base": 0x400000,
            "timer_period_ms": 20, "callbacks_per_logic_budget": 2,
            "nominal_logic_hz": 25, "maximum_logic_budget": 2,
            "counters": COUNTERS, "assertions_passed": len(checks),
            "runtime_observed": False}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exe", type=Path)
    parser.add_argument("--objdump", default="objdump")
    args = parser.parse_args()
    try:
        print(json.dumps(audit(args.exe, args.objdump), indent=2))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Audit refused: {error}\n")


if __name__ == "__main__":
    main()
