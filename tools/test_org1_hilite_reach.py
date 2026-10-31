#!/usr/bin/env python3
"""Asset-free checks for conservative ORG1 animated-hilite diagnostics."""
import itertools
import sys
import unittest

sys.dont_write_bytecode = True
import org1_hilite_reach as reach


IDENTITY = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]


def part(hilites, vertices):
    return dict(hilites=len(hilites), hilite_list=hilites,
                partcel_list=[dict(vertices=vertices)])


class HiliteReachTests(unittest.TestCase):
    def test_all_parts_and_all_hilites_are_scanned(self):
        static = dict(incomplete=False, parts=[part([], []),
                      part([(0, 1, 0), (0, 1, 1)], [1, 2, 3, 4, 5, 6]),
                      part([(0, 1, 0)], [7, 8, 9])])
        probes = list(reach.all_hilites(static))
        self.assertEqual([(p[0], p[1]) for p in probes], [(1, 0), (1, 1), (2, 0)])
        self.assertEqual(probes[-1][3], [7, 8, 9])

    def test_nonvertex_and_imported_collision_parts_reject(self):
        for static in (dict(incomplete=False, parts=[part([(0, 2, 0)], [1, 2, 3])]),
                       dict(incomplete=False, parts=[part([], [])] * 15 +
                            [part([(0, 1, 0)], [1, 2, 3])])):
            with self.assertRaises(ValueError):
                list(reach.all_hilites(static))

    def test_invalid_target_rejects_without_python_negative_slicing(self):
        for target in (-2, 2, 0.5, True):
            static = dict(incomplete=False,
                          parts=[part([(0, 1, target)], [1, 2, 3, 4, 5, 6])])
            with self.assertRaises(ValueError):
                list(reach.all_hilites(static))

    def test_affine_envelope_includes_root_extremes(self):
        matrix = [4096, 512, 0, -512, 4096, 0, 0, 0, 4096, 72, -144, 33]
        vertex = [7, -78, 71]
        low, high = reach.affine_probe_envelope(matrix, vertex)
        for row in itertools.product((-32768, -4096, 0, 4096, 32767), repeat=3):
            root = list(row) * 3
            point = reach.transformed_probe(matrix, vertex, root)
            self.assertTrue(all(low <= value <= high for value in point))

    def test_short_wrap_and_negative_shift(self):
        self.assertEqual(reach.short(32768), -32768)
        self.assertEqual(reach.short_interval((32760, 32770)), reach.SHORT)
        matrix = IDENTITY.copy()
        matrix[0] = 1
        self.assertEqual(reach.transformed_probe(matrix, [-1, 0, 0], reach.ROOTS[0][1]), [-1, 0, 0])

    def test_accumulator_overflow_rejects(self):
        with self.assertRaises(ValueError):
            reach.dot_interval([32767] * 3)

    def test_interpolated_action_rejects(self):
        action = dict(valid=True, flags=1, parts=16)
        xar = dict(code=2, static_count=1, sets=[([(0, 16, 1, ())], [action.copy() for _ in range(34)])])
        self.assertEqual(len(reach.discrete_actions(xar, 16)), 34)
        xar['sets'][0][1][-1]['flags'] = 2
        with self.assertRaises(ValueError):
            reach.discrete_actions(xar, 16)

    def test_candidate_change_rejects(self):
        with self.assertRaises(ValueError):
            reach.traffic_hilite_reach({}, dict(candidate_x=[-512, 512], candidate_z=[-225, 480]))


if __name__ == '__main__':
    unittest.main()
