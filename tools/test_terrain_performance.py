"""Asset-free tests for profiler framing and machine-specific acceptance policy."""
import struct
import unittest
from godot_profile import decode, encode
from run_terrain_performance import meets_target


class PerformanceTests(unittest.TestCase):
    def test_profiler_commands_round_trip(self):
        command = ['profiler:servers', 2**40, [True, [2048, False]]]
        self.assertEqual(decode(encode(command)), command)

    def test_numeric_and_packed_monitor_data(self):
        self.assertEqual(decode(struct.pack('<Id', 3 | 65536, 0.005)), 0.005)
        self.assertEqual(decode(struct.pack('<IIff', 32, 2, 1.0, 2.0)), [1.0, 2.0])

    def test_object_and_trailing_data_are_rejected(self):
        with self.assertRaises(ValueError):
            decode(struct.pack('<I', 24))
        with self.assertRaises(ValueError):
            decode(encode('x') + b'junk')

    def test_wrong_display_or_incomplete_run_cannot_pass(self):
        report = dict(accepted=True, window_size=[2560, 1440], renderer='gl_compatibility',
                      vsync=0, max_fps=0, draw_calls_max=400)
        self.assertTrue(meets_target(report))
        for field, value in [('accepted', False), ('window_size', [640, 480]),
                             ('renderer', 'dummy'), ('vsync', 1), ('max_fps', 144),
                             ('draw_calls_max', 0)]:
            self.assertFalse(meets_target(report | {field: value}), field)


if __name__ == '__main__':
    unittest.main()
