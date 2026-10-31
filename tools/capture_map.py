"""Capture the map viewer windowed into an external folder, under either rendering profile."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import struct
import sys
import tempfile
import zlib
from godot_project import isolated_project
from run_gameplay_capture import add_rendering_arguments, engine_arguments, rendering_method, shader_error

MAP_VIEWER = 'res://scenes/tools/map_viewer.tscn'
IGNORED_ERROR = re.compile(r'ERROR: Failed to read the root certificate store\.[\r\n]+\s+at: get_system_ca_certificates[^\r\n]*')
FAILURE_PATTERN = re.compile(r'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:')
SUCCESS_PATTERN = re.compile(r'map capture .*: OK')
CAPTURE_PATTERN = re.compile(r'map capture (.+\.png): OK')
PNG_SIGNATURE = b'\x89PNG\r\n\x1a\n'
PNG_CHANNELS = {2: 3, 6: 4}


def projection(value):
    """A projection distance of 0 (viewer default) or 3..8192."""
    number = int(value)
    if number != 0 and not 3 <= number <= 8192:
        raise argparse.ArgumentTypeError('must be 0 or 3..8192')
    return number


def tick(value):
    """A start tick in 0..100000."""
    number = int(value)
    if not 0 <= number <= 100000:
        raise argparse.ArgumentTypeError('must be 0..100000')
    return number


def parse_arguments(argv=None):
    """Parse the command line; the output folder is validated by output_folder."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--output-directory', required=True, help='Absolute folder outside the repository')
    parser.add_argument('--level', default='SUB1')
    parser.add_argument('--camera', choices=('default', 'map-slice'), default='map-slice')
    parser.add_argument('--camera-source', default='')
    parser.add_argument('--camera-target', default='')
    parser.add_argument('--projection', type=projection, default=0)
    parser.add_argument('--tick', type=tick, default=0)
    parser.add_argument('--low-poly', action='store_true')
    parser.add_argument('--linear', action='store_true')
    parser.add_argument('--benchmark', action='store_true')
    parser.add_argument('--probe-model', default='')
    add_rendering_arguments(parser)
    return parser, parser.parse_args(argv)


def output_folder(value, repo):
    """The normalized absolute capture folder, or raise ValueError when it is relative or inside the repository."""
    if not os.path.isabs(value):
        raise ValueError('Output directory must be absolute.')
    folder = Path(os.path.normpath(os.path.abspath(value)))
    repo = Path(os.path.normpath(os.path.abspath(repo)))
    if folder == repo or repo in folder.parents:
        raise ValueError('Captures must stay outside the repository.')
    return folder


def viewer_arguments(args, folder):
    """User arguments passed to the map viewer after --."""
    arguments = ['--level=' + args.level, '--camera=' + args.camera, '--tick=' + str(args.tick),
                 '--low-poly=' + str(args.low_poly).lower(), '--linear=' + str(args.linear).lower(),
                 '--screenshot-dir=' + str(folder)]
    if args.benchmark:
        arguments.append('--benchmark')
    if args.probe_model:
        arguments.append('--probe-model=' + args.probe_model)
    if args.camera_source:
        arguments.append('--camera-source=' + args.camera_source)
    if args.camera_target:
        arguments.append('--camera-target=' + args.camera_target)
    if args.projection != 0:
        arguments.append('--projection=' + str(args.projection))
    arguments.append('--rendering=' + args.rendering)
    return arguments


def import_command(godot, project, log):
    """The headless import command that refreshes the class cache before the capture."""
    return [godot, '--headless', '--disable-crash-handler', '--path', str(project), '--log-file', str(log), '--import']


def capture_command(args, project, log, folder):
    """The windowed map viewer command, with the rendering method before the scene."""
    method = rendering_method(args.rendering, args.rendering_method)
    return ([args.godot, '--disable-crash-handler', '--path', str(project), '--log-file', str(log)]
            + engine_arguments(method) + [MAP_VIEWER, '--'] + viewer_arguments(args, folder))


def capture_failure(text, returncode):
    """Why a capture log fails, or None when it shows an OK capture without errors."""
    if returncode:
        return 'exit code %d' % returncode
    line = shader_error(text)
    if line:
        return 'shader error: ' + line
    for line in IGNORED_ERROR.sub('', text).splitlines():
        if FAILURE_PATTERN.search(line):
            return 'error: ' + line.strip()
    if not SUCCESS_PATTERN.search(text):
        return 'no "map capture ...: OK" line'
    return None


def _paeth(left, up, corner):
    estimate = left + up - corner
    distances = (abs(estimate - left), abs(estimate - up), abs(estimate - corner))
    return (left, up, corner)[distances.index(min(distances))]


def png_rows(data):
    """Unfiltered rows of an 8-bit, non-interlaced RGB or RGBA PNG, or None for other layouts."""
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError('not a PNG file')
    offset = len(PNG_SIGNATURE)
    header = None
    compressed = b''
    while offset + 8 <= len(data):
        length, kind = struct.unpack('>I4s', data[offset:offset + 8])
        body = data[offset + 8:offset + 8 + length]
        offset += 12 + length
        if kind == b'IHDR':
            header = struct.unpack('>IIBBBBB', body)
        elif kind == b'IDAT':
            compressed += body
        elif kind == b'IEND':
            break
    if header is None:
        raise ValueError('PNG without IHDR')
    width, height, depth, colour, _, _, interlace = header
    if depth != 8 or interlace or colour not in PNG_CHANNELS:
        return None
    step = PNG_CHANNELS[colour]
    stride = width * step
    raw = zlib.decompress(compressed)
    rows = []
    previous = bytearray(stride)
    for index in range(height):
        start = index * (stride + 1)
        kind = raw[start]
        row = bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            left = row[x - step] if x >= step else 0
            up = previous[x]
            corner = previous[x - step] if x >= step else 0
            if kind == 1:
                row[x] = (row[x] + left) & 255
            elif kind == 2:
                row[x] = (row[x] + up) & 255
            elif kind == 3:
                row[x] = (row[x] + ((left + up) >> 1)) & 255
            elif kind == 4:
                row[x] = (row[x] + _paeth(left, up, corner)) & 255
        rows.append(bytes(row))
        previous = row
    return step, rows


def uniform_png(data):
    """Whether every pixel of a PNG has one colour; None when the layout is not checked."""
    decoded = png_rows(data)
    if decoded is None:
        return None
    step, rows = decoded
    if not rows or not rows[0]:
        return True
    expected = rows[0][:step] * (len(rows[0]) // step)
    return all(row == expected for row in rows)


def blank_capture(text):
    """The first reported capture whose image is a single colour, or None."""
    for path in CAPTURE_PATTERN.findall(text):
        image = Path(path.strip())
        if image.is_file() and uniform_png(image.read_bytes()):
            return str(image)
    return None


def godot_executable(name):
    """The Godot executable on PATH, falling back to the default macOS application bundle."""
    found = shutil.which(name)
    if found:
        return found
    bundle = Path('/Applications/Godot.app/Contents/MacOS/Godot')
    if name == 'godot' and sys.platform == 'darwin' and bundle.is_file():
        return str(bundle)
    return name


def run(command, cwd, env):
    """Run one Godot process and return its exit code."""
    startup = None
    if os.name == 'nt':
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
    return subprocess.run(command, cwd=cwd, env=env, startupinfo=startup, stdout=subprocess.DEVNULL,
                          stderr=subprocess.STDOUT, timeout=1800).returncode


def main(argv=None):
    parser, args = parse_arguments(argv)
    repo = Path(__file__).resolve().parents[1]
    try:
        folder = output_folder(args.output_directory, repo)
    except ValueError as error:
        parser.error(str(error))
    godot = godot_executable(args.godot)
    args.godot = godot
    run_directory = Path(tempfile.mkdtemp(prefix='frogger-map-capture-'))
    profile = run_directory / 'appdata'
    temporary = run_directory / 'temp'
    profile.mkdir()
    temporary.mkdir()
    folder.mkdir(parents=True, exist_ok=True)
    project = isolated_project(repo, profile)
    env = os.environ.copy()
    env.update(APPDATA=str(profile), XDG_DATA_HOME=str(profile), TEMP=str(temporary), TMP=str(temporary))
    import_log = run_directory / 'import.log'
    code = run(import_command(godot, project, import_log), repo, env)
    text = import_log.read_text(encoding='utf-8') if import_log.exists() else ''
    if code or not text or re.search(r'SCRIPT ERROR|Parse Error|Failed to load script', text):
        print(text)
        print('capture_map: import failed; see %s' % import_log)
        return 1
    log = run_directory / 'capture.log'
    print('capture_map: log %s' % log, flush=True)
    code = run(capture_command(args, project, log, folder), repo, env)
    text = log.read_text(encoding='utf-8') if log.exists() else ''
    print(text)
    failure = capture_failure(text, code)
    blank = None if failure else blank_capture(text)
    if blank:
        failure = 'capture is a single colour: ' + blank
    if failure:
        print('capture_map: FAILED, %s' % failure)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
