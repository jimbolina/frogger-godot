"""Regression checks for demo trace integrity and comparison semantics."""
import json
import subprocess
import sys
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
        equal = compare(rows, rows, self.status(), 0)
        self.assertTrue(equal['accepted'])
        self.assertTrue(equal['terminal_comparable'])
        self.assertEqual({}, equal['terminal_differences'])
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

    def test_zero_tick_incomplete_reports_uncomparable_terminal(self):
        reference = [self.row(3, map_id=24, action=2), self.row(4, map_id=24)]
        status = self.status(0, 0, 'incomplete')
        status['duration'] = 724
        status.update(map=24, reason='Demo requires unsupported camera zones')
        report = compare(reference, [], status, 24)
        self.assertFalse(report['complete'])
        self.assertFalse(report['accepted'])
        self.assertFalse(report['terminal_comparable'])
        self.assertIsNone(report['terminal_differences'])
        self.assertEqual(status['reason'], report['termination_reason'])
        self.assertEqual(0, report['actual_ticks'])
        self.assertEqual(0, report['first_input_divergence'])
        self.assertEqual([], report['actual_route'])

    def test_empty_actual_requires_consistent_incomplete_status(self):
        reference = [self.row(0, map_id=24)]
        valid = self.status(0, 0, 'incomplete')
        valid['duration'] = 724
        valid.update(map=24, reason='guard rejected playback')
        variants = [
            dict(valid, status='complete'),
            dict(valid, status='complete', duration=0),
            dict(valid, elapsed_ticks=1),
            dict(valid, consumed_inputs=1),
            dict(valid, reason=''),
            dict(valid, reason='  '),
            dict(valid, reason=None),
            {key: value for key, value in valid.items() if key != 'reason'},
            dict(valid, map=23),
            {key: value for key, value in valid.items() if key != 'map'},
        ]
        for status in variants:
            with self.subTest(status=status), self.assertRaises(ValueError):
                compare(reference, [], status, 24)

    def test_status_integrity(self):
        rows = [self.row(0)]
        valid = self.status(1, 0)
        variants = [
            None, [], dict(valid, schema='other'), dict(valid, status='pending'),
            dict(valid, duration=-1), dict(valid, elapsed_ticks=True),
            dict(valid, consumed_inputs=False), dict(valid, consumed_inputs=-1),
            {key: value for key, value in valid.items() if key != 'duration'},
        ]
        for status in variants:
            with self.subTest(status=status), self.assertRaises(ValueError):
                compare(rows, rows, status, 0)

    def test_cli_zero_tick_status_before_empty_rejection(self):
        header = ','.join(FROG_COLUMNS) + '\n'
        reference = [self.row(0, map_id=24, action=2)]
        status = self.status(0, 0, 'incomplete')
        status['duration'] = 724
        status.update(map=24, reason='guard rejected playback')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'reference.csv').write_text(
                header + ','.join(map(str, reference[0].values())) + '\n')
            (root / 'actual.csv').write_text(header)
            (root / 'status.json').write_text(json.dumps(status))
            command = [sys.executable, str(Path(__file__).with_name('compare_demo_trace.py')),
                       str(root / 'reference.csv'), str(root / 'actual.csv'),
                       '--status', str(root / 'status.json'), '--map', '24']
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(1, result.returncode, result.stderr)
            self.assertEqual(status['reason'], json.loads(result.stdout)['termination_reason'])
            for alteration in (dict(status, status='complete'), dict(status, reason='')):
                (root / 'status.json').write_text(json.dumps(alteration))
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(2, result.returncode, result.stdout)
            (root / 'status.json').write_text('{')
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(2, result.returncode)
            (root / 'status.json').unlink()
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(2, result.returncode)
            (root / 'status.json').write_text(json.dumps(status))
            (root / 'reference.csv').write_text(header)
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(2, result.returncode)
            (root / 'reference.csv').write_text(
                header + ','.join(map(str, reference[0].values())) + '\n')
            result = subprocess.run(command + ['--segment', '1'], capture_output=True, text=True)
            self.assertEqual(2, result.returncode)
            (root / 'actual.csv').write_text(header.rstrip())
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(2, result.returncode)
            (root / 'actual.csv').write_text(header.replace('call', 'tick', 1))
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(2, result.returncode)
            (root / 'actual.csv').write_bytes(header.replace('\n', '\r\n').encode())
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(2, result.returncode)

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
