"""Asset-free refusal checks for the narrow PC timing tools."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import subprocess

import audit_pc_timing as audit
import observe_pc_timing as observe


class TimingToolChecks(unittest.TestCase):
    def test_unknown_identity_refused_before_disassembly(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "synthetic.exe"
            path.write_bytes(b"synthetic test input, not retail data")
            with patch.object(audit.subprocess, "run") as run:
                with self.assertRaisesRegex(ValueError, "Unsupported executable"):
                    audit.audit(path, "unused")
                run.assert_not_called()

    def test_missing_static_assertion_refused(self):
        with patch.object(audit, "verify_identity", return_value=audit.RETAIL_SHA256):
            with patch.object(audit.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "")):
                with self.assertRaisesRegex(ValueError, "Static timing assertion failed"):
                    audit.audit(Path("synthetic.exe"), "unused")

    def test_repository_output_refused(self):
        with self.assertRaisesRegex(ValueError, "outside the repository"):
            observe.output_path(Path(__file__).resolve().parent / "refusal.csv")

    def test_existing_output_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "observation.csv"
            path.touch()
            with self.assertRaisesRegex(ValueError, "already exists"):
                observe.output_path(path)

    def test_frozen_output_refused(self):
        frozen = Path(__file__).resolve().parents[2] / "froggy" / "refusal.csv"
        with self.assertRaisesRegex(ValueError, "frozen reference"):
            observe.output_path(frozen)

    def test_summary_counts_wrap_but_not_consumed_budget(self):
        rows = [[0, 10, 0xFFFFFFFE, 2, 0xFFFFFFFF],
                [1_000_000_000, 1_000_000_010, 48, 0, 24]]
        result = observe.summarize(rows)
        self.assertEqual(result["callback_delta_modulo_u32"], 50)
        self.assertEqual(result["global_logic_delta_modulo_u32"], 25)
        self.assertEqual(result["callback_hz"], 50)
        self.assertEqual(result["global_logic_hz"], 25)
        self.assertEqual(result["budget_decreases_observed"], 1)
        self.assertEqual(result["elapsed_uncertainty_ns"], 10)

    def test_summary_stationary_does_not_infer_pause(self):
        result = observe.summarize([[0, 2, 10, 0, 5], [1_000_000_000, 1_000_000_002, 10, 0, 5]])
        self.assertEqual(result["global_logic_hz"], 0)
        self.assertNotIn("paused", result)

    def test_unsupported_os_refused_before_process_access(self):
        with patch.object(observe.os, "name", "posix"):
            with self.assertRaisesRegex(ValueError, "Only Windows"):
                observe.observe(123, Path("unused"), Path("unused"), 1, .01)


if __name__ == "__main__":
    unittest.main()
