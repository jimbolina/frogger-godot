"""Small self-tests for strict path JSONL schedule comparison."""

import copy
import json
from pathlib import Path
import tempfile
import unittest

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.inspection.verify_path_schedules import compare_traces, read_trace


class PathTraceComparisonTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.path = Path(self.folder.name) / 'path.jsonl'
        self.metadata = {
            'schema': 'path-run-v1', 'scenario': 'line', 'source_id': 'synthetic:line',
            'resource_id': -1, 'path_index': -1, 'source_offset': -1,
            'level_code': '', 'tick_limit': 1,
            'start': {'segment_index': 0, 'distance': 0, 'speed': 1, 'flags': 9},
            'diagnostics': [],
        }
        self.state = {
            'tick_index': 0, 'segment_index': 0, 'segment_type': 2,
            'segment_distance': 0, 'segment_length': 10, 'segment_param': 0,
            'total_distance': 0, 'speed': 1, 'flags': 9,
            'position': [0, 0, 0], 'tangent': [4096, 0, 0],
        }

    def write(self, rows, name='path.jsonl'):
        path = Path(self.folder.name) / name
        path.write_text('\n'.join(json.dumps(row) for row in rows) + '\n', encoding='utf-8')
        return path

    def valid(self):
        first = copy.deepcopy(self.state)
        second = dict(first, tick_index=1, segment_distance=1, total_distance=1,
                      position=[1, 0, 0])
        return [copy.deepcopy(self.metadata), first, second]

    def test_complete_equal_traces(self):
        left = self.write(self.valid())
        right = self.write(self.valid(), 'other.jsonl')
        self.assertEqual(len(read_trace(left)), 3)
        compare_traces(left, right)

    def test_zero_tick_trace_has_initial_snapshot(self):
        self.metadata['tick_limit'] = 0
        self.assertEqual(len(read_trace(self.write([self.metadata, self.state]))), 2)

    def test_rejects_missing_extra_and_reordered_rows(self):
        rows = self.valid()
        for broken in (rows[:-1], rows + [rows[-1]], [rows[0], rows[2], rows[1]]):
            with self.assertRaises(ValueError):
                read_trace(self.write(broken))

    def test_rejects_missing_field_and_changed_metadata(self):
        rows = self.valid()
        del rows[1]['tangent']
        with self.assertRaises(ValueError):
            read_trace(self.write(rows))
        left = self.write(self.valid())
        changed = self.valid()
        changed[0] = dict(changed[0], source_id='other')
        right = self.write(changed, 'changed.jsonl')
        with self.assertRaisesRegex(ValueError, 'differs at metadata'):
            compare_traces(left, right)


if __name__ == '__main__':
    unittest.main()
