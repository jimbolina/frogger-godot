"""Asset-free tests for profiler framing and machine-specific acceptance policy."""
import struct
import unittest
from godot_profile import decode, encode, visual_frames
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

    def test_visual_profile_excludes_warmup_and_retains_stage_intervals(self):
        def packet(frame):
            return ['visual:profile_frame', 1,
                    [frame, 9, 'Begin', 1.0, 2.0, 'Opaque', 3.0, 5.0, 'End', 7.0, 10.0]]

        rows = visual_frames([packet(10), packet(11), packet(12)], 10, 11)
        self.assertEqual(rows, [dict(frame=11, cpu_ms=6.0, gpu_ms=8.0, intervals=[
            dict(stage='Begin', cpu_ms=2.0, gpu_ms=3.0),
            dict(stage='Opaque', cpu_ms=4.0, gpu_ms=5.0)])])
        with self.assertRaisesRegex(ValueError, 'No visual profiler frames'):
            visual_frames([packet(10)], 10, 11)
        incomplete = packet(11)
        incomplete[2].pop()
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            visual_frames([incomplete], 10, 11)

    def test_wrong_display_or_incomplete_run_cannot_pass(self):
        report = dict(accepted=True, window_size=[2560, 1440], renderer='gl_compatibility',
                      render_target_size=[1920, 1440], bars=[320, 0], vsync=0, max_fps=0,
                      draw_calls_max=400, mode='full', smoothing=True, outcome_ok=True,
                      high_detail=True, entity_count=64, overlay_visible=True, inspector_visible=True,
                      profiler_active=False, trace_active=False,
                      cadence_ok=True, fps=201, frames={'p99_ms': 5}, ticks=730, tick_limit=730,
                      engine=dict(major=4, minor=5, patch=1), cpu='Intel i7-10700K', gpu='NVIDIA RTX 4070 Ti SUPER')
        self.assertTrue(meets_target(report))
        for field, value in [('accepted', False), ('window_size', [640, 480]),
                             ('renderer', 'dummy'), ('vsync', 1), ('max_fps', 144),
                             ('draw_calls_max', 0), ('render_target_size', [960, 720]),
                             ('bars', [0, 0]), ('mode', 'paused'), ('smoothing', False),
                             ('high_detail', False), ('entity_count', 63), ('overlay_visible', False),
                             ('inspector_visible', False), ('profiler_active', True), ('trace_active', True),
                             ('outcome_ok', False), ('cadence_ok', False), ('fps', 200),
                             ('frames', {'p99_ms': 5.001}), ('ticks', 729), ('cpu', 'other'),
                             ('gpu', 'other'), ('engine', dict(major=4, minor=5, patch=2))]:
            self.assertFalse(meets_target(report | {field: value}), field)


if __name__ == '__main__':
    unittest.main()
