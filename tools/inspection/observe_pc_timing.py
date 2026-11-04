"""Read three audited counters from one explicitly supplied Windows retail PID."""
import argparse
import csv
import ctypes
import json
import os
import time
from ctypes import wintypes
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT
from tools.inspection.audit_pc_timing import COUNTERS, verify_identity


def output_path(value: Path) -> Path:
    path = value.resolve()
    repo = REPO_ROOT
    if path == repo or repo in path.parents:
        raise ValueError("Observation output must be outside the repository")
    frozen = (repo.parent / "froggy").resolve()
    if path == frozen or frozen in path.parents:
        raise ValueError("Observation output must be outside the frozen reference")
    if any(candidate.exists() for candidate in (path, path.with_suffix(path.suffix + ".json"),
                                                 path.with_suffix(path.suffix + ".summary.json"))):
        raise ValueError("Observation output already exists")
    if not path.parent.is_dir():
        raise ValueError("Observation output parent must already exist")
    return path


def summarize(rows: list) -> dict:
    if len(rows) < 2:
        return {"sample_count": len(rows), "rates_available": False}
    elapsed_ns = ((rows[-1][0] + rows[-1][1]) - (rows[0][0] + rows[0][1])) / 2
    totals = [0, 0]
    resets = 0
    for previous, current in zip(rows, rows[1:]):
        for index, column in enumerate((2, 4)):
            totals[index] += (current[column] - previous[column]) & 0xFFFFFFFF
        resets += int(current[3] < previous[3])
    seconds = elapsed_ns / 1e9
    uncertainty_ns = (rows[0][1] - rows[0][0] + rows[-1][1] - rows[-1][0]) / 2
    return {"sample_count": len(rows), "rates_available": seconds > 0,
            "elapsed_seconds_midpoints": seconds,
            "elapsed_uncertainty_ns": uncertainty_ns,
            "maximum_read_window_ns": max(row[1] - row[0] for row in rows),
            "callback_delta_modulo_u32": totals[0],
            "global_logic_delta_modulo_u32": totals[1],
            "callback_hz": totals[0] / seconds if seconds > 0 else None,
            "global_logic_hz": totals[1] / seconds if seconds > 0 else None,
            "budget_decreases_observed": resets,
            "interpretation": "Unsigned wrap assumed for monotonic counters; resets cannot be distinguished. Budget is consumed/reset, not accumulated. Focus and pause are not inferred."}


def observe(pid: int, exe: Path, output: Path, duration: float, interval: float) -> None:
    if os.name != "nt":
        raise ValueError("Only Windows process observation is supported")
    if not 0 < duration <= 300 or not 0.001 <= interval <= 1 or pid <= 0:
        raise ValueError("Require positive PID, duration (0,300], interval [0.001,1]")
    output = output_path(output)
    expected = exe.resolve(strict=True)
    digest = verify_identity(expected)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.CloseHandle.restype = wintypes.BOOL
    kernel.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD,
                                                 wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
    kernel.QueryFullProcessImageNameW.restype = wintypes.BOOL
    kernel.ReadProcessMemory.argtypes = [wintypes.HANDLE, ctypes.c_void_p,
                                         ctypes.c_void_p, ctypes.c_size_t,
                                         ctypes.POINTER(ctypes.c_size_t)]
    kernel.ReadProcessMemory.restype = wintypes.BOOL
    handle = kernel.OpenProcess(0x0010 | 0x1000, False, pid)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        buffer = ctypes.create_unicode_buffer(32768)
        size = wintypes.DWORD(len(buffer))
        if not kernel.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
            raise ctypes.WinError(ctypes.get_last_error())
        actual = Path(buffer.value).resolve(strict=True)
        if not os.path.samefile(actual, expected):
            raise ValueError("PID image path differs from explicitly supplied executable")
        verify_identity(actual)
        def read(address: int, length: int) -> bytes:
            data = ctypes.create_string_buffer(length)
            count = ctypes.c_size_t()
            if not kernel.ReadProcessMemory(handle, address, data, length, ctypes.byref(count)):
                raise ctypes.WinError(ctypes.get_last_error())
            if count.value != length:
                raise ValueError("Short process-memory read")
            return data.raw
        if read(0x400000, 2) != b"MZ":
            raise ValueError("Audited image is not loaded at its preferred base")
        pe_offset = int.from_bytes(read(0x40003C, 4), "little")
        if not 0x40 <= pe_offset <= 4096:
            raise ValueError("Invalid in-memory PE header offset")
        if read(0x400000 + pe_offset, 4) != b"PE\0\0":
            raise ValueError("Invalid in-memory PE signature")
        if int.from_bytes(read(0x400000 + pe_offset + 52, 4), "little") != 0x400000:
            raise ValueError("Unexpected preferred image base")
        metadata = {"pid": pid, "exe": str(actual), "sha256": digest,
                    "duration_seconds": duration, "interval_seconds": interval,
                    "clock": "perf_counter_ns", "counter_addresses": COUNTERS,
                    "counter_reads_atomic": False,
                    "identity_limit": "Path and current file hash verified; no claim about code patched in process memory or concurrent file replacement",
                    "global_frame_attribution": "source-shaped static match; increment bypassed by retail pause branch"}
        with output.with_suffix(output.suffix + ".json").open("x", encoding="utf-8") as metadata_stream:
            metadata_stream.write(json.dumps(metadata, indent=2) + "\n")
        with output.open("x", newline="", encoding="utf-8") as stream:
            writer = csv.writer(stream)
            writer.writerow(["read_start_ns", "read_end_ns", *COUNTERS])
            end = time.perf_counter() + duration
            rows = []
            while time.perf_counter() < end:
                start_ns = time.perf_counter_ns()
                values = [int.from_bytes(read(address, 4), "little") for address in COUNTERS.values()]
                row = [start_ns, time.perf_counter_ns(), *values]
                rows.append(row)
                writer.writerow(row)
                stream.flush()
                time.sleep(interval)
        summary = summarize(rows)
        with output.with_suffix(output.suffix + ".summary.json").open("x", encoding="utf-8") as summary_stream:
            summary_stream.write(json.dumps(summary, indent=2) + "\n")
        print(json.dumps(summary, indent=2))
    finally:
        kernel.CloseHandle(handle)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--exe", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--duration", type=float, default=30)
    parser.add_argument("--interval", type=float, default=0.01)
    args = parser.parse_args()
    try:
        observe(args.pid, args.exe, args.output, args.duration, args.interval)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Observation refused: {error}\n")


if __name__ == "__main__":
    main()
