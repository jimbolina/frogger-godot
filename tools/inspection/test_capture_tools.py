"""Godot-free tests for the capture launchers' command lines and log verdicts; run with Python directly."""
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zlib
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT
from tools.inspection import capture_map
from tools.inspection import run_gameplay_capture as gameplay

SHADER_LOG = '''Godot Engine v4.5.1.stable.official
SHADER ERROR: Unknown identifier in expression: 'ambient_global'.
          at: (null) (:12)
map capture SUB1: OK
'''
OK_LOG = '''Godot Engine v4.5.1.stable.official
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1)
map capture SUB1: OK
'''


def png(width, height, pixel, filter_kind=0, odd=None):
    """A small 8-bit RGBA PNG of one colour, optionally with one differing pixel."""
    rows = []
    for y in range(height):
        row = bytearray(pixel * width)
        if odd and odd[0] == y:
            row[odd[1] * 4:odd[1] * 4 + 4] = odd[2]
        if filter_kind == 1:
            row = bytearray([row[x] if x < 4 else (row[x] - row[x - 4]) & 255 for x in range(len(row))])
        rows.append(bytes([filter_kind]) + bytes(row))

    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(b''.join(rows))) + chunk(b'IEND', b''))


class GameplayCaptureTest(unittest.TestCase):
    def keyboard(self, *argv):
        _, args = gameplay.parse_arguments(['--output-directory', '/external'] + list(argv))
        stages = gameplay.capture_stages(args, None, Path('/external/run'))
        name, arguments, headless = stages[-1]
        self.assertEqual((name, headless), ('keyboard', False))
        return gameplay.stage_command('godot', Path('/project'), Path('/external/k.log'), headless,
                                      args.resolution, arguments)

    def test_keyboard_stage_keeps_the_project_method(self):
        command = self.keyboard()
        self.assertNotIn('--rendering-method', command)
        self.assertEqual(command[command.index('--resolution') + 1], '640x480')
        self.assertLess(command.index('-s'), command.index('--'))
        self.assertTrue(command[-1].startswith('--output='))

    def test_game_arguments_follow_the_probe_arguments(self):
        command = self.keyboard('--game-argument=--effect-shadows=retail')
        self.assertEqual(command[-1], '--effect-shadows=retail')
        self.assertTrue(command[-2].startswith('--output='))

    def test_rendering_options_are_rejected(self):
        for argv in (['--rendering', 'modern'], ['--rendering-method', 'gl_compatibility']):
            with self.assertRaises(SystemExit):
                with open(os.devnull, 'w') as sink:
                    stderr, sys.stderr = sys.stderr, sink
                    try:
                        gameplay.parse_arguments(['--output-directory', '/external'] + argv)
                    finally:
                        sys.stderr = stderr

    def test_headless_stages_take_no_resolution(self):
        command = gameplay.stage_command('godot', Path('/project'), Path('/l.log'), True, '640x480', ['--import'])
        self.assertNotIn('--resolution', command)
        self.assertIn('--headless', command)

    def test_shader_errors_fail_with_the_line(self):
        self.assertEqual(gameplay.shader_error(SHADER_LOG),
                         "SHADER ERROR: Unknown identifier in expression: 'ambient_global'.")
        self.assertIn('ambient_global', gameplay.log_failure(SHADER_LOG))
        self.assertIsNone(gameplay.log_failure('gameplay_capture: PASS\n'))
        self.assertEqual(gameplay.log_failure('CHECK FAILED x\n'), 'CHECK FAILED')


class MapCaptureTest(unittest.TestCase):
    repo = REPO_ROOT
    folder = Path(os.path.abspath(os.sep)) / 'external' / 'captures'

    def command(self, *argv):
        _, args = capture_map.parse_arguments(['--output-directory', str(self.folder)] + list(argv))
        return capture_map.capture_command(args, Path('/project'), Path('/run/capture.log'), self.folder)

    def test_default_command_matches_the_powershell_capture(self):
        command = self.command()
        scene = command.index(capture_map.MAP_VIEWER)
        self.assertNotIn('--rendering-method', command)
        self.assertEqual(command[scene + 1], '--')
        self.assertEqual(command[scene + 2:], [
            '--level=SUB1', '--tick=0', '--low-poly=false', '--linear=false',
            '--screenshot-dir=' + str(self.folder)])

    def test_optional_viewer_arguments(self):
        command = self.command('--level', 'ORG1', '--tick', '30', '--low-poly', '--linear', '--benchmark',
                               '--camera-source', '1,2,3', '--camera-target', '4,5,6')
        user = command[command.index('--') + 1:]
        for expected in ('--level=ORG1', '--tick=30', '--low-poly=true', '--linear=true', '--benchmark',
                         '--camera-source=1,2,3', '--camera-target=4,5,6'):
            self.assertIn(expected, user)

    def test_output_folder_must_be_absolute_and_external(self):
        with self.assertRaises(ValueError):
            capture_map.output_folder('relative/captures', self.repo)
        with self.assertRaises(ValueError):
            capture_map.output_folder(str(self.repo), self.repo)
        with self.assertRaises(ValueError):
            capture_map.output_folder(str(self.repo / 'captures' / '..' / 'out'), self.repo)
        self.assertEqual(capture_map.output_folder(str(self.folder), self.repo), self.folder)

    def test_capture_verdicts(self):
        self.assertIsNone(capture_map.capture_failure(OK_LOG, 0))
        self.assertIn('ambient_global', capture_map.capture_failure(SHADER_LOG, 0))
        self.assertEqual(capture_map.capture_failure(OK_LOG, 1), 'exit code 1')
        self.assertEqual(capture_map.capture_failure('ERROR: broken\nmap capture SUB1: OK\n', 0),
                         'error: ERROR: broken')
        self.assertIsNotNone(capture_map.capture_failure('map capture SUB1: FAILED\n', 0))

    def test_single_colour_captures_are_detected(self):
        black = bytes([0, 0, 0, 255])
        self.assertTrue(capture_map.uniform_png(png(5, 4, black)))
        self.assertTrue(capture_map.uniform_png(png(5, 4, black, filter_kind=1)))
        self.assertFalse(capture_map.uniform_png(png(5, 4, black, odd=(3, 4, bytes([0, 9, 0, 255])))))
        self.assertFalse(capture_map.uniform_png(png(5, 4, black, filter_kind=1, odd=(2, 0, bytes([1, 0, 0, 255])))))
        with tempfile.TemporaryDirectory(prefix='frogger-capture-test-') as directory:
            image = Path(directory) / 'map.png'
            image.write_bytes(png(3, 3, black))
            log = 'map capture %s: OK\n' % image
            self.assertEqual(capture_map.blank_capture(log), str(image))
            image.write_bytes(png(3, 3, black, odd=(1, 1, bytes([255, 255, 255, 255]))))
            self.assertIsNone(capture_map.blank_capture(log))

    def test_invalid_ranges_are_rejected(self):
        for argv in (['--tick', '-1'], ['--camera', 'map-slice'], ['--projection', '512'],
                     ['--probe-model', 'GEN_FROG'], ['--rendering', 'modern']):
            with self.assertRaises(SystemExit):
                with open(os.devnull, 'w') as sink:
                    stderr, sys.stderr = sys.stderr, sink
                    try:
                        capture_map.parse_arguments(['--output-directory', str(self.folder)] + argv)
                    finally:
                        sys.stderr = stderr


if __name__ == '__main__':
    unittest.main()
