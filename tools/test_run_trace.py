"""Regression checks for complete terrain JSONL transport validation."""
import json
from pathlib import Path
import tempfile
import unittest

from compare_run_trace import read


class CompleteTraceTests(unittest.TestCase):
    def trace(self, limit=2, ticks=2, completed=False):
        rows = [{'schema': 'terrain-run-v1', 'tick_limit': limit}]
        for tick in range(ticks):
            for phase in ('control', 'move', 'collision', 'camera', 'final'):
                rows.append({'tick': tick, 'phase': phase,
                             'state': {'completed': completed and tick == ticks - 1 and phase == 'final'}})
        return rows

    def validate(self, rows):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'trace.jsonl'
            path.write_text('\n'.join(json.dumps(row) for row in rows), encoding='utf-8')
            return read(path)

    def test_complete_zero_and_terminal_prefix(self):
        for rows in (self.trace(), self.trace(0, 0), self.trace(2, 1, True)):
            self.assertEqual(rows, self.validate(rows))

    def test_missing_or_reordered_phase(self):
        missing = self.trace()
        del missing[3]
        reordered = self.trace()
        reordered[1], reordered[2] = reordered[2], reordered[1]
        for rows in (missing, reordered):
            with self.assertRaisesRegex(ValueError, 'ordered tick/phase'):
                self.validate(rows)

    def test_identically_truncated_inputs_each_fail(self):
        rows = self.trace(2, 1)
        for _ in range(2):
            with self.assertRaisesRegex(ValueError, 'truncated execution'):
                self.validate(rows)

    def test_extra_unknown_error_and_post_completion(self):
        unknown = self.trace()
        unknown[1]['phase'] = 'unknown'
        error = self.trace()
        error[1]['error'] = 'unsupported'
        terminal = self.trace()
        terminal[5]['state']['completed'] = True
        for rows in (self.trace(1, 2), unknown, error, terminal):
            with self.assertRaises(ValueError):
                self.validate(rows)


if __name__ == '__main__':
    unittest.main()
