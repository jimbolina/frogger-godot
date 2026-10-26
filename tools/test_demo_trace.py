"""Regression checks for demo trace integrity and comparison semantics."""
import tempfile
from pathlib import Path
import unittest

from compare_demo_trace import FROG_COLUMNS, compare, read_csv


class DemoTraceTests(unittest.TestCase):
    def row(self, call, map_id=0, x=1, action=-1):
        return dict(zip(FROG_COLUMNS, (call, 7, map_id, 0, x, 2, x * 256, 0, 512, 0, 3, action)))

    def status(self, ticks=2, inputs=1, state='complete'):
        return {'schema': 'demo-playback-v1', 'status': state,
                'duration': ticks, 'elapsed_ticks': ticks, 'consumed_inputs': inputs}

    def test_equal_and_different_terminal(self):
        rows = [self.row(3, action=1), self.row(4)]
        self.assertTrue(compare(rows, rows, self.status(), 0)['accepted'])
        changed = [self.row(0, action=1), self.row(1, x=2)]
        self.assertFalse(compare(rows, changed, self.status(), 0)['accepted'])

    def test_route_and_input_are_diagnostics(self):
        reference = [self.row(8, x=2, action=2), self.row(9)]
        actual = [self.row(0, action=1), self.row(1)]
        report = compare(reference, actual, self.status(), 0)
        self.assertTrue(report['accepted'])
        self.assertFalse(report['route_equal'])
        self.assertEqual(0, report['first_input_divergence'])

    def test_incomplete_and_truncated_status(self):
        rows = [self.row(0, action=1), self.row(1)]
        self.assertFalse(compare(rows, rows, self.status(state='incomplete'), 0)['accepted'])
        false_complete = self.status()
        false_complete['duration'] = 3
        with self.assertRaisesRegex(ValueError, 'duration'):
            compare(rows, rows, false_complete, 0)
        with self.assertRaisesRegex(ValueError, 'elapsed_ticks'):
            compare(rows, rows[:1], self.status(), 0)

    def test_transition_selects_map_visit_without_call_alignment(self):
        reference = [self.row(7), self.row(8, 1), self.row(9, action=1), self.row(10)]
        actual = [self.row(0, action=1), self.row(1)]
        self.assertTrue(compare(reference, actual, self.status(), 0, 1)['accepted'])
        with self.assertRaises(ValueError):
            compare(reference, actual, self.status(), 0, 2)

    def test_malformed_csv(self):
        header = ','.join(FROG_COLUMNS) + '\n'
        row = ','.join(map(str, self.row(0).values())) + '\n'
        for text in (header, header + row.rstrip(), header + row + row,
                     header + row.replace(',7,', ',x,'), header + row.replace('\n', '\r\n'),
                     header + row.replace(',0,1,2,', ',2,1,2,')):
            with self.subTest(text=text), tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / 'trace.csv'
                path.write_text(text)
                with self.assertRaises(ValueError):
                    read_csv(path)


if __name__ == '__main__':
    unittest.main()
