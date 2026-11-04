#!/usr/bin/env python3
"""Independent retail PC game-over page facts and scripted page traces.

Transcribes GameOverStartup, GameOverUpdate and GameOverShutdown (tempopt.c),
the duration defines (tempopt.h) and the GAME OVER sprite (OPTIONS.C), then
adds what the vendored source lacks from the retail executable's compiled page
(FROGGER.EXE: GameOverStartup 0x00443630, GameOverUpdate 0x00443700,
GameOverShutdown 0x00443800, the viewport shrink 0x00435490/0x004354e0): disc
track 22 once, effects muted, the HUD viewport hidden and the game viewport
shrunk into the centre each tick after the predelay. Replays the page's 30 Hz
update over scripted fire ticks at the PC's 640x480 display. With
FROGGER_DATA_DIR (or --data-dir) set, the executable facts are compared with
the bytes of FROGGER.EXE through its PE section table. See
tests/golden/specs/frontend.md#game-over.
"""
import argparse
import difflib
import json
from pathlib import Path
import os
import re
import struct
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden import make_golden_frontend as frontend
from tools.golden import make_golden_stack as stack

ROOT = frontend.ROOT
GAME_OVER_JSON = frontend.GOLDEN / 'synthetic' / 'frontend_game_over.json'
SOUND_CFG = ROOT / 'archive' / 'third_party' / 'froglord_cfg' / 'sounds' / '1997-11-19-pc-retail.cfg'

DISPLAY_W, DISPLAY_H = 640, 480

DURATION = 105
PREDELAY_SECONDS, TICKS_PER_SECOND = 2, 30
PREDELAY = PREDELAY_SECONDS * TICKS_PER_SECOND
FADE_TICKS = 30
FIRE_BEFORE_END = 15
START_UNITS = DURATION + PREDELAY
GATE_UNITS = DURATION + FADE_TICKS
FIRE_UNITS = DURATION - FIRE_BEFORE_END
GREY_MAX = 0xFF
GREY_SHIFT = 1
SHRINK_SHIFT = 2
SHRINK_STEPS = START_UNITS >> SHRINK_SHIFT
WIDTH_STEP = DISPLAY_H // SHRINK_STEPS

JINGLE_TRACK = 22
ZONE_TRACK_BASE = 22
FX_VOLUME_CHANNEL = 2
VOLUME_STAGES = 8
VP_NO_DISPLAY = 0x4
HARDWARE_BIT = 0x1
CONTINUE_PAGE = 0x11
FIRE_PAD_BIT = 0x2
IMAGE = ('OPTION_TEXT_GAMEOVER', 'opt_gameover')
EXIT_EVENT = 'GAME_OVER_DONE'

SOUNDS = {'SFX_GEN_FROG_CROAK': (3, 'GEN_FROG_CROAK')}
SOUND_CROAK = SOUNDS['SFX_GEN_FROG_CROAK'][0]

IMAGE_BASE = 0x00400000
TEXT_VMA = 0x00401000

ROW_COLUMNS = ['tick', 'units', 'view_x', 'view_y', 'view_w', 'view_h', 'sprite_grey', 'accepts_fire',
               'overlay_visible']
SAMPLE_TICKS = [1, 30, 31, 45, 60, 75, 76, 89, 90, 120, 165]


def le32(value):
    return struct.pack('<I', value & 0xFFFFFFFF).hex()


def rel32(address, length, target):
    """An e8 call at address whose instruction is length bytes long, to target."""
    return 'e8' + le32(target - (address + length))


def call(address, target):
    return rel32(address, 5, target)


def exe_pins():
    """Retail instruction bytes the page rests on: address, bytes and meaning."""
    pins = [
        (0x0044367d, '8b0d24514900' 'f6c1%02x' '741a' % HARDWARE_BIT,
         'GameOverStartup: the sprite turns black only with display-capability bit 0 set '
         '(ds:0x495124 & 1, the hardware path)'),
        (0x004436a2, 'c705c0ab4800' + le32(START_UNITS),
         'GameOverStartup: Options_count_down_units = 165 (GAME_OVER_DURATION + GAME_OVER_PREDELAY)'),
        (0x004436ac, 'c7055c544800' + le32(1), 'GameOverStartup: Game_over_no_new_sound = TRUE'),
        (0x004436b6, '6a00' '6a%02x' % FX_VOLUME_CHANNEL + call(0x004436ba, 0x0044cd40),
         'GameOverStartup: MRSNDSetVolumeLevel(MRSND_FX_VOLUME, 0) at 0x0044cd40: every effect is silent'),
        (0x004436c2, call(0x004436c2, 0x004300e0), 'GameOverStartup: StopCD at 0x004300e0'),
        (0x004436c7, '6a00' '6a%02x' % JINGLE_TRACK + call(0x004436cb, 0x004300a0),
         'GameOverStartup: PlayCD(22, 0) at 0x004300a0: disc track 22 once, the game-over jingle'),
        (0x004436d3, 'a1c0ab4800' 'c1e8%02x' '50' '6a00' % SHRINK_SHIFT + call(0x004436de, 0x00435490),
         'GameOverStartup: shrink setup 0x00435490(0, units >> 2): 41 steps'),
        (0x004436e6, '8b0d94504900' '804908%02x' % VP_NO_DISPLAY,
         'GameOverStartup: Game_viewporth->vp_flags |= MR_VP_NO_DISPLAY: the HUD hides'),
        (0x00443734, 'bf' + le32(CONTINUE_PAGE) + 'bb' + le32(GATE_UNITS),
         'GameOverUpdate: edi = 0x11 (retail OPTIONS_PAGE_CONTINUE), ebx = 135 (GAME_OVER_DURATION + 30)'),
        (0x00443753, 'a1c0ab4800' '48' 'a3c0ab4800' '3bc3' '737b' '85c0' '7420',
         'GameOverUpdate: units -= 1; nothing more while units >= 135; units == 0 requests CONTINUE'),
        (0x00443766, 'a1c0ab4800' '83f8%02x' '731c' 'a00cce4800' 'a8%02x' '7413' % (FIRE_UNITS, FIRE_PAD_BIT),
         'GameOverUpdate: fire (FR_GO pressed) counts only while units < 90 (GAME_OVER_DURATION - 15)'),
        (0x00443779, '555555' '6a%02x' % SOUND_CROAK + call(0x0044377e, 0x0044c290) + '83c410' '893d00854900',
         'GameOverUpdate: MRSNDPlaySound(SFX_GEN_FROG_CROAK) at 0x0044c290, then Option_page_request = CONTINUE'),
        (0x0044378c, call(0x0044378c, 0x004354e0),
         'GameOverUpdate: the shrink step 0x004354e0 every tick after the predelay, the exit tick included'),
        (0x00443791, 'a124514900' 'a8%02x' '7443' '8bc3' '8b0dc0ab4800' '2bc1' 'b9' % HARDWARE_BIT + le32(FADE_TICKS) +
         '8bd0' 'c1e008' '2bc2' '2bd2' 'f7f1' '3d' + le32(GREY_MAX) + '7205' 'b8' + le32(GREY_MAX) + 'd1f8',
         'GameOverUpdate: hardware path only, grey = min(255, (135 - units) * 255 / 30) >> 1'),
        (0x00443805, 'c7055c544800' + le32(0) + '80480c01',
         'GameOverShutdown: Game_over_no_new_sound = FALSE; the sprite gets MR_SPF_NO_DISPLAY'),
        (0x0044381c, 'c1e007' '2bc1' '99' '83e2%02x' '03c2' 'c1f8%02x' '50' '6a%02x' % (
            VOLUME_STAGES - 1, VOLUME_STAGES.bit_length() - 1, FX_VOLUME_CHANNEL) + call(0x0044382d, 0x0044cd40),
         'GameOverShutdown: MRSNDSetVolumeLevel(MRSND_FX_VOLUME, 127 * Sound_volume / 8)'),
        (0x0043549e, 'a164474900' '83f801' '7529' 'a180504900' '2bd2' '0fbf4810' '83c012' '890d44514900'
         '0fbf08' '890d54514900' '0fbf00' 'f774240c' 'a364514900',
         'Shrink setup: single player only; width and height from the viewport (+0x10, +0x12); '
         'step = height / steps (480 / 41 = 11)'),
        (0x00435500, 'a144514900' '8b0d64514900' '2bc1' '85c0' '7f02' '33c0' 'a344514900'
         '0fbf0da4514900' '0fbf05a6514900' '0faf0544514900' '99' 'f7f9',
         'Shrink step: width = max(0, width - step); height = display_h * width / display_w'),
        (0x0043554b, 'a1c8514900' '668954240a' '2bc3' 'd1f8' '8d4c2404' '6689442404' '51' 'a12c514900' '2bc2'
         '8b15b8504900' 'd1f8' '52' '668944240e' + call(0x00435578, 0x0044d710),
         'Shrink step: x = (Game_display_width - width) >> 1, y = (Game_display_height - height) >> 1, '
         'MRChangeViewport at 0x0044d710'),
        (0x0043e580, '6a00' 'a118514900' '83c0%02x' '50' % ZONE_TRACK_BASE + call(0x0043e58b, 0x004300a0),
         'Level complete (not this page): PlayCD(theme + 22, 0), so tracks 23-32 are the zone-complete tunes'),
    ]
    return [{'address': '0x%08x' % address, 'bytes_hex': data, 'meaning': meaning}
            for address, data, meaning in pins]


class Page:
    """GameOverStartup's count-down and shrink setup and GameOverUpdate's tick."""

    def __init__(self, quit):
        self.quit = quit
        self.units = START_UNITS
        self.shrink_steps = self.units >> SHRINK_SHIFT
        self.width_step = DISPLAY_H // self.shrink_steps
        self.view_w, self.view_h = DISPLAY_W, DISPLAY_H
        self.sprite_grey = 0
        self.frame = 0
        self.sounds = []
        self.exit = None

    def accepts_fire(self):
        return self.exit is None and self.units < FIRE_UNITS

    def overlay_visible(self):
        return self.units < GATE_UNITS

    def view_rect(self):
        return [(DISPLAY_W - self.view_w) >> 1, (DISPLAY_H - self.view_h) >> 1, self.view_w, self.view_h]

    def tick(self, fire):
        if self.exit is not None:
            return
        self.frame += 1
        self.sounds = []
        self.units -= 1
        if self.units >= GATE_UNITS:
            return
        if self.units == 0:
            self.exit = EXIT_EVENT
        elif self.units < FIRE_UNITS and fire:
            self.sounds.append(SOUND_CROAK)
            self.exit = EXIT_EVENT
        self.view_w = max(0, self.view_w - self.width_step)
        self.view_h = DISPLAY_H * self.view_w // DISPLAY_W
        self.sprite_grey = min(GREY_MAX, (GATE_UNITS - self.units) * GREY_MAX // FADE_TICKS) >> GREY_SHIFT

    def row(self):
        return [self.frame, self.units] + self.view_rect() + [self.sprite_grey, self.accepts_fire(),
                                                              self.overlay_visible()]


TRACES = [
    ('timeout', False, []),
    ('fire_early', False, [40]),
    ('fire_skip', False, [76]),
    ('fire_edge', False, [75, 100]),
    ('quit', True, []),
]


def run(name, quit, fire_ticks):
    page = Page(quit)
    rows, sounds_at = {}, {}
    for tick in range(1, START_UNITS + 1):
        page.tick(tick in fire_ticks)
        rows[tick] = page.row()
        if page.sounds:
            sounds_at[str(tick)] = list(page.sounds)
        if page.exit is not None:
            break
    exit_tick = page.frame
    sample = sorted(t for t in set(SAMPLE_TICKS + [exit_tick]) if t <= exit_tick)
    return {'name': name, 'quit': quit, 'fire_ticks': fire_ticks, 'exit_tick': exit_tick,
            'exit_event': page.exit, 'sounds_at': sounds_at, 'rows': [rows[t] for t in sample]}


def table():
    page = Page(False)
    rows = []
    for _ in range(START_UNITS):
        page.tick(False)
        rows.append(page.row())
    return rows


def document():
    start = Page(False)
    return {
        'source': 'tempopt.h:43-44, tempopt.c:4057-4175 GameOverStartup/Update/Shutdown, OPTIONS.C:641-643; '
                  'FROGGER.EXE 0x00443630/0x00443700/0x00443800 and the shrink 0x00435490/0x004354e0',
        'constants': {'duration': DURATION, 'predelay': PREDELAY, 'fade_ticks': FADE_TICKS,
                      'fire_units': FIRE_UNITS, 'gate_units': GATE_UNITS, 'start_units': START_UNITS,
                      'shrink_steps': SHRINK_STEPS, 'width_step': WIDTH_STEP, 'jingle_track': JINGLE_TRACK,
                      'sound_croak': SOUND_CROAK, 'display_width': DISPLAY_W, 'display_height': DISPLAY_H,
                      'image': IMAGE[1], 'continue_page': CONTINUE_PAGE, 'zone_track_base': ZONE_TRACK_BASE},
        'startup': {'units': start.units, 'shrink_steps': start.shrink_steps, 'width_step': start.width_step,
                    'view': start.view_rect(), 'sprite_grey': start.sprite_grey, 'startup_track': JINGLE_TRACK,
                    'mutes_effects': True, 'hides_hud': True, 'exit_event': None},
        'row_columns': ROW_COLUMNS,
        'ticks': table(),
        'traces': [run(*trace) for trace in TRACES],
        'exe': {'file': 'FROGGER.EXE', 'image_base': '0x%08x' % IMAGE_BASE, 'text_vma': '0x%08x' % TEXT_VMA},
        'exe_pins': exe_pins(),
    }


def dump(value, indent=0):
    """JSON with flat lists and short leaf records on one line, everything else expanded."""
    pad, inner = ' ' * indent, ' ' * (indent + 1)
    line = json.dumps(value, separators=(', ', ': '))
    rows = isinstance(value, list) and any(isinstance(v, list) for v in value)
    leaf = isinstance(value, dict) and all(stack.flat(v) for v in value.values()) and len(line) <= 120
    if (stack.flat(value) and not rows) or leaf:
        return line
    if isinstance(value, dict):
        items = [inner + json.dumps(k) + ': ' + dump(v, indent + 1) for k, v in value.items()]
        return '{\n' + ',\n'.join(items) + '\n' + pad + '}'
    return '[\n' + ',\n'.join(inner + dump(v, indent + 1) for v in value) + '\n' + pad + ']'


def strip_c(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    return stack.squash(text)


def c_snippets():
    """Statements of tempopt.c built from the transcribed offsets, comments and whitespace removed."""
    colour = ''.join('Gameover_title_sprite_ptr->sp_core.sc_base_colour.%s=%s;' % (c, '%s') for c in 'rgb')
    return [
        'texture0=Options_text_textures[%s][Game_language];UpdateSpriteDisplay(Gameover_title_sprite_ptr,texture0,'
        '(Game_display_width>>1)-(texture0->te_w>>1),(Game_display_height>>1)-(texture0->te_h>>1));' % IMAGE[0]
        + colour % ('0', '0', '0'),
        'Options_count_down_units=GAME_OVER_DURATION+GAME_OVER_PREDELAY;Game_over_no_new_sound=TRUE;'
        '#ifdefPSX#ifdefPSX_ENABLE_XAMRSNDSetVolumeLevel(MRSND_FX_VOLUME,0);',
        'OptUpdateGame();LiveEntityChangeVolume(0,FALSE);Options_count_down_units--;'
        'if(Options_count_down_units<GAME_OVER_DURATION+%d){if(!Options_count_down_units)'
        '{Option_page_request=OPTIONS_PAGE_CONTINUE;}else{if(Options_count_down_units<GAME_OVER_DURATION-%d'
        '&&MR_CHECK_PAD_PRESSED(Frog_input_ports[0],FR_GO)){MRSNDPlaySound(SFX_GEN_FROG_CROAK,NULL,0,0);'
        'Option_page_request=OPTIONS_PAGE_CONTINUE;}}' % (FADE_TICKS, FIRE_BEFORE_END),
        'i=MIN(0x%x,((GAME_OVER_DURATION+%d-Options_count_down_units)*0x%x)/%d);'
        % (GREY_MAX, FADE_TICKS, GREY_MAX, FADE_TICKS),
        'i>>=%d;' % GREY_SHIFT + colour % ('i', 'i', 'i') + 'GamePauseAddPrim();}',
        'Game_over_no_new_sound=FALSE;MakeSpriteInvisible(Gameover_title_sprite_ptr);'
        'MRSNDSetVolumeLevel(MRSND_FX_VOLUME,(127*Sound_volume)/OPTIONS_SOUND_STAGES);',
    ]


def check_c(c_root):
    """Compare the transcriptions above with the frozen C; returns problems and the number of checks."""
    problems = []
    header = (c_root / 'tempopt.h').read_text(encoding='latin-1')
    expected = {'GAME_OVER_DURATION': str(DURATION),
                'GAME_OVER_PREDELAY': '(%d*%d)' % (TICKS_PER_SECOND, PREDELAY_SECONDS)}
    for name, value in expected.items():
        if stack.define(header, name) != value:
            problems.append('tempopt.h %s is %s, transcribed %s' % (name, stack.define(header, name), value))
    tempopt = strip_c((c_root / 'tempopt.c').read_text(encoding='latin-1'))
    for snippet in c_snippets():
        if snippet not in tempopt:
            problems.append('tempopt.c no longer contains: %s' % snippet[:100])
    raw = (c_root / 'tempopt.c').read_text(encoding='latin-1')
    match = re.search(r'\{\s*&im_(\w+),[^}]*\},\s*//\s*%s,' % IMAGE[0], raw)
    if not match or match.group(1) != IMAGE[1]:
        problems.append('tempopt.c %s is not im_%s' % IMAGE)
    options = strip_c((c_root / 'OPTIONS.C').read_text(encoding='latin-1'))
    if ('texture=Options_text_textures[%s][Game_language];Gameover_title_sprite_ptr=MRCreate2DSprite('
            '(Game_display_width>>1)-(texture->te_w>>1),(Game_display_height>>1)-(texture->te_h>>1),'
            'Option_viewport_ptr,texture,NULL);MakeSpriteInvisible(Gameover_title_sprite_ptr);'
            % IMAGE[0]) not in options:
        problems.append('OPTIONS.C GAME OVER sprite creation differs')
    if stack.define(header, 'OPTIONS_SOUND_STAGES') != str(VOLUME_STAGES):
        problems.append('tempopt.h OPTIONS_SOUND_STAGES is not %d' % VOLUME_STAGES)
    sound = (c_root / 'sound.h').read_text(encoding='latin-1')
    body = re.search(r'In the GENERIC VAB\.\s*(.*?)\}', sound, flags=re.S)
    generic = re.findall(r'^\s*(SFX_\w+)\s*,', body.group(1), flags=re.M) if body else []
    for name, (value, _froglord) in SOUNDS.items():
        if name not in generic or generic.index(name) != value:
            problems.append('sound.h %s is not %d' % (name, value))
    return problems, len(expected) + len(c_snippets()) + 3 + len(SOUNDS)


def check_sound_names():
    problems = []
    generic, section = [], None
    for line in SOUND_CFG.read_text(encoding='utf-8').splitlines():
        line = line.split('#')[0].strip()
        if line.startswith('['):
            section = line
        elif line and section == '[GENERIC]':
            generic.append(line)
    for name, (value, froglord) in SOUNDS.items():
        if generic[value] != froglord:
            problems.append('%s is %s in FrogLord, not %s' % (name, generic[value], froglord))
    return problems


def pe_sections(data):
    """Image base and (name, virtual address, virtual size, raw size, raw offset) from the PE headers."""
    if data[:2] != b'MZ':
        raise ValueError('no MZ header')
    pe = struct.unpack_from('<I', data, 0x3C)[0]
    if data[pe:pe + 4] != b'PE\0\0':
        raise ValueError('no PE signature')
    count, = struct.unpack_from('<H', data, pe + 6)
    optional_size, = struct.unpack_from('<H', data, pe + 20)
    optional = pe + 24
    if struct.unpack_from('<H', data, optional)[0] != 0x10B:
        raise ValueError('not a PE32 optional header')
    image_base, = struct.unpack_from('<I', data, optional + 28)
    sections = []
    for index in range(count):
        at = optional + optional_size + 40 * index
        name = data[at:at + 8].rstrip(b'\0').decode('latin-1')
        vsize, vaddr, raw_size, raw_offset = struct.unpack_from('<IIII', data, at + 8)
        sections.append((name, vaddr, vsize, raw_size, raw_offset))
    return image_base, sections


def check_exe(exe_path):
    """Compare the pinned instruction bytes with FROGGER.EXE; returns problems and the pin count."""
    data = exe_path.read_bytes()
    try:
        image_base, sections = pe_sections(data)
    except ValueError as error:
        return ['%s: %s' % (exe_path, error)], 0
    problems = []
    if image_base != IMAGE_BASE:
        problems.append('image base is 0x%08x, not 0x%08x' % (image_base, IMAGE_BASE))
    text = [s for s in sections if s[0] == '.text']
    if not text or image_base + text[0][1] != TEXT_VMA:
        problems.append('.text does not start at 0x%08x' % TEXT_VMA)
        return problems, 0
    _name, vaddr, vsize, raw_size, raw_offset = text[0]
    start = image_base + vaddr
    pins = exe_pins()
    for pin in pins:
        address = int(pin['address'], 16)
        expected = bytes.fromhex(pin['bytes_hex'])
        if not (start <= address and address + len(expected) <= start + min(vsize, raw_size)):
            problems.append('%s lies outside .text' % pin['address'])
            continue
        offset = raw_offset + address - start
        actual = data[offset:offset + len(expected)]
        if actual != expected:
            problems.append('%s (file offset 0x%x) is %s, pinned %s: %s'
                            % (pin['address'], offset, actual.hex(), pin['bytes_hex'], pin['meaning']))
    return problems, len(pins)


def find_exe(data_dir):
    for child in sorted(data_dir.iterdir()) if data_dir.is_dir() else []:
        if child.name.upper() == 'FROGGER.EXE' and child.is_file():
            return child
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--c-reference', type=Path, default=frontend.DEFAULT_C,
                        help='frozen C source folder (default: ../froggy/engine/vendor/frogger-psx-src/source)')
    parser.add_argument('--data-dir', default=os.environ.get('FROGGER_DATA_DIR', ''),
                        help='retail folder with FROGGER.EXE (default: $FROGGER_DATA_DIR)')
    parser.add_argument('--check', action='store_true', help='compare with the committed file instead of writing')
    args = parser.parse_args()
    problems = check_sound_names()
    if args.c_reference.is_dir():
        c_problems, count = check_c(args.c_reference)
        problems += c_problems
        if not c_problems:
            print('C cross-check passed against %s (%d checks)' % (args.c_reference, count))
    else:
        print('C source not found at %s; cross-checks skipped' % args.c_reference)
    if args.data_dir:
        exe = find_exe(Path(args.data_dir))
        if exe is None:
            problems.append('no FROGGER.EXE in %s' % args.data_dir)
        else:
            exe_problems, count = check_exe(exe)
            problems += exe_problems
            if not exe_problems:
                print('Executable pins passed against %s (%d pins)' % (exe, count))
    else:
        print('FROGGER_DATA_DIR not set; executable pins skipped')
    for problem in problems:
        print('cross-check: ' + problem)
    if problems:
        sys.exit(1)
    text = dump(document()) + '\n'
    if args.check:
        old = GAME_OVER_JSON.read_text(encoding='utf-8') if GAME_OVER_JSON.exists() else ''
        if old != text:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                       str(GAME_OVER_JSON), 'generated', n=0))
        print('Committed facts differ from the generator' if old != text else 'Committed facts match the generator')
        sys.exit(1 if old != text else 0)
    GAME_OVER_JSON.write_text(text, encoding='utf-8')
    print('Wrote %s' % GAME_OVER_JSON.relative_to(ROOT))


if __name__ == '__main__':
    main()
