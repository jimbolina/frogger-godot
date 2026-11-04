#!/usr/bin/env python3
"""Independent retail in-game pause facts and scripted pause traces.

Transcribes GamePause, the hidden Continue/Quit and Yes/No menus and the fade
polygon (pause.c, pause.h), the option images (tempopt.c) and the menu glow
(OPTIONS.C OptionUpdateSpcores), then replays the pause's 30 Hz arms over
scripted ticks at the PC's 640x480 display. The port shows the hidden menu at
INIT and reads Escape for FRR_START.

Also transcribes the retail PC pause-cheat dispatcher (exe 0x0042fda0: four
DirectInput scancode phrases with one cursor each and a key-down gate, pinned
to the exe bytes in froggy's frogger_cheat_sequences.h), replays scripted key
traces through it alone and through the pause, and applies the unlock cheats
(pause.c:933-998, :1017-1021) to the retail level-select stack.

The CD music comes from the retail executable, whose GamePause (0x0042f200)
stops the CD at INIT (PauseCD) and restarts the level track at KILL_SPRITES
and on Yes (ResumeCD, PlayCD of the kept track, looping), where pause.c's PC
arm is empty. With FROGGER_DATA_DIR (or --data-dir) set, those facts are
compared with the bytes of FROGGER.EXE through its PE section table.
See tests/golden/specs/frontend.md#pause-page.
"""
import copy
import argparse
import difflib
import json
from pathlib import Path
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_golden_frontend as frontend
import make_golden_game_over as game_over
import make_golden_level_complete as level_complete
import make_golden_stack as stack

ROOT = frontend.ROOT
PAUSE_JSON = frontend.GOLDEN / 'synthetic' / 'frontend_pause.json'
SOUND_CFG = ROOT / 'archive' / 'third_party' / 'froglord_cfg' / 'sounds' / '1997-11-19-pc-retail.cfg'
DEFAULT_FROGGY = ROOT.parent / 'froggy' / 'engine'
CHEAT_H = Path('asset_pipeline') / 'include' / 'frogger_cheat_sequences.h'
WINSYS_H = Path('PC') / 'winsys.h'

DISPLAY_W, DISPLAY_H = 640, 480
CENTRE_X, CENTRE_Y = DISPLAY_W >> 1, DISPLAY_H >> 1

FADE_STEP = 0x10
FADE_END = 0x80
GLOW_MASK, GLOW_SHIFT = 0x7, 5

SOUNDS = {'SFX_GEN_FROG_CROAK': (3, 'GEN_FROG_CROAK'), 'SFX_GEN_FROG_HOP': (6, 'GEN_FROG_HOP')}
HOP_SOUND = SOUNDS['SFX_GEN_FROG_HOP'][0]
CROAK_SOUND = SOUNDS['SFX_GEN_FROG_CROAK'][0]

QUIT_YES, QUIT_NO, QUIT_ITEMS = 0, 1, 2
CONTINUE_SELECTED, QUIT_SELECTED, MENU_ITEMS = 0, 1, 2

IMAGES = {'PAUSED': ('OPTION_TEXT_PAUSED', 'opt_paused'),
          'CONTINUE': ('OPTION_TEXT_BIG_CONTINUE', 'opt_big_continue'),
          'QUIT': ('OPTION_TEXT_QUIT', 'quit'),
          'YES': ('OPTION_TEXT_YES', 'opt_yes'),
          'NO': ('OPTION_TEXT_NO', 'opt_no')}
RISE = {'PAUSED': 0, 'CONTINUE': 32, 'QUIT': 48, 'YES': 64, 'NO': 64}
SIDE = {'PAUSED': 0, 'CONTINUE': 0, 'QUIT': 0, 'YES': 48, 'NO': -48}
SPRITE_ORDER = ['PAUSED', 'CONTINUE', 'QUIT', 'YES', 'NO']
WIDTHS = {'opt_paused': 160, 'opt_big_continue': 193, 'quit': 96, 'opt_yes': 63, 'opt_no': 48}

BUTTONS = ('escape', 'up', 'down', 'left', 'right', 'fire')

MODES = ['NO_PAUSE', 'INIT', 'FADE_DOWN', 'MENU', 'KILL_SPRITES', 'FADE_UP', 'DEINIT']
GAME_PAUSE = 0x0042f200
ARM_TABLE = 0x0042f91c
ARMS = [0x0042f219, 0x0042f2e7, 0x0042f39a, 0x0042f401, 0x0042f7cb, 0x0042f805, 0x0042f874]
PAUSE_MODE = 0x00478354
PLAY_CD, PAUSE_CD, RESUME_CD = level_complete.PLAY_CD, level_complete.PAUSE_CD, level_complete.RESUME_CD
PLAY_SOUND = level_complete.PLAY_SOUND

DIK = {}
for row, first in (('QWERTYUIOP', 0x10), ('ASDFGHJKL', 0x1E), ('ZXCVBNM', 0x2C), (' ', 0x39)):
    DIK.update({letter: first + i for i, letter in enumerate(row)})
LETTER = {code: letter for letter, code in DIK.items()}
SPACE = DIK[' ']

CHEAT_END = 0xFFFFFFFF
CHEATS = [
    ('INFINITE_LIVES', 'LIVES', 0x00077378, 'NO MORE ROAD SPLATS', 'pause.c:900', True,
     [0x31, 0x18, 0x39, 0x32, 0x18, 0x13, 0x12, 0x39, 0x13, 0x18, 0x1E, 0x20, 0x39, 0x1F, 0x19, 0x26, 0x1E,
      0x14, 0x1F]),
    ('ALL_ZONES', 'ZONES', 0x000773C8, 'SHOW ME MORE ZONES PLEASE', 'pause.c:933', True,
     [0x1F, 0x23, 0x18, 0x11, 0x39, 0x32, 0x12, 0x39, 0x32, 0x18, 0x13, 0x12, 0x39, 0x2C, 0x18, 0x31, 0x12,
      0x1F, 0x39, 0x19, 0x26, 0x12, 0x1E, 0x1F, 0x12]),
    ('ALL_LEVELS', 'LEVELS', 0x00077430, 'WAY TOO HARD FOR THE LIKES OF ME', 'pause.c:986', True,
     [0x11, 0x1E, 0x15, 0x39, 0x14, 0x18, 0x18, 0x39, 0x23, 0x1E, 0x13, 0x20, 0x39, 0x21, 0x18, 0x13, 0x39,
      0x14, 0x23, 0x12, 0x39, 0x26, 0x17, 0x25, 0x12, 0x1F, 0x39, 0x18, 0x21, 0x39, 0x32, 0x12]),
    ('TIMEOUT_DEATHS', 'TIMEOUT', 0x000774B8, 'NO MORE TIMEOUT DEATHS PLEASE', 'exe 0x00430040', False,
     [0x31, 0x18, 0x39, 0x32, 0x18, 0x13, 0x12, 0x39, 0x14, 0x17, 0x32, 0x12, 0x18, 0x16, 0x14, 0x39, 0x20,
      0x12, 0x1E, 0x14, 0x23, 0x1F, 0x39, 0x19, 0x26, 0x12, 0x1E, 0x1F, 0x12]),
]
CHEAT_NAMES = [name for name, *_ in CHEATS]
CHEAT_CROAKS = {name: croaks for name, _, _, _, _, croaks, _ in CHEATS}
SEQUENCE = {name: seq for name, _, _, _, _, _, seq in CHEATS}

LEVEL = frontend.LEVEL
ZONE_UNLOCK = [
    ('assign', 'CAVES1'), ('zone', 'CAVES3'), ('zone', 'CAVES4'),
    ('assign', 'SKY1'), ('zone', 'SKY2'), ('zone', 'SKY3'), ('zone', 'SKY4'),
    ('assign', 'SWAMP1'), ('zone', 'SWAMP2'), ('zone', 'SWAMP3'), ('zone', 'SWAMP4'), ('zone', 'SWAMP5'),
    ('assign', 'DESERT1'), ('zone', 'DESERT2'), ('zone', 'DESERT3'), ('zone', 'DESERT4'), ('zone', 'DESERT5'),
    ('assign', 'JUNGLE1'),
]


class Pause:
    """GamePause from the press tick on, with the hidden menu created at INIT."""

    def __init__(self, sound_volume, cheats=None, arcade=True):
        self.mode = 'INIT'
        self.menu_mode = 'CONTINUE'
        self.cheats = cheats
        self.arcade = arcade
        self.sound_volume = sound_volume
        self.volume = sound_volume
        self.fade = 0
        self.selection = CONTINUE_SELECTED
        self.quit_selection = QUIT_NO
        self.frame = 0
        self.paused_selection = 0
        self.events = []

    def tick(self, keys, down=()):
        self.events = []
        self.down = list(down)
        if self.mode == 'NO_PAUSE':
            return
        self.frame += 1
        arm = getattr(self, 'arm_' + self.mode.lower())
        arm(keys)

    def arm_init(self, _keys):
        self.events.append('STOP_MUSIC')
        self.paused_selection = 0
        self.mode = 'FADE_DOWN'
        self.volume = self.sound_volume
        self.menu_mode = 'CONTINUE'
        self.selection = CONTINUE_SELECTED
        self.quit_selection = QUIT_NO

    def arm_fade_down(self, _keys):
        self.fade = (self.fade + FADE_STEP) & 0xFF
        self.volume = 0 if self.volume < 1 else self.volume - 1
        if self.fade == FADE_END:
            self.mode = 'MENU'

    def arm_menu(self, keys):
        if 'escape' in keys:
            self.paused_selection = 0
            self.mode = 'KILL_SPRITES'
            self.events.append('HOP')
            return
        if self.arcade and self.cheats is not None:
            for name in self.cheats.check(self.down):
                if CHEAT_CROAKS[name]:
                    self.events.append('CROAK')
                self.events.append('CHEAT_' + name)
        if self.menu_mode == 'CONTINUE':
            if 'down' in keys and self.selection < MENU_ITEMS - 1:
                self.selection += 1
                self.events.append('HOP')
            if 'up' in keys and self.selection > 0:
                self.selection -= 1
                self.events.append('HOP')
            if 'fire' in keys:
                if self.selection == CONTINUE_SELECTED:
                    self.paused_selection = CONTINUE_SELECTED
                    self.mode = 'KILL_SPRITES'
                else:
                    self.menu_mode = 'QUIT'
                    self.quit_selection = QUIT_NO
                self.events.append('CROAK')
        else:
            if 'left' in keys and self.quit_selection < QUIT_ITEMS - 1:
                self.quit_selection += 1
                self.events.append('HOP')
            if 'right' in keys and self.quit_selection > 0:
                self.quit_selection -= 1
                self.events.append('HOP')
            if 'fire' in keys:
                if self.quit_selection == QUIT_NO:
                    self.paused_selection = CONTINUE_SELECTED
                    self.mode = 'KILL_SPRITES'
                    self.events.append('CROAK')
                else:
                    self.paused_selection = QUIT_SELECTED
                    self.mode = 'DEINIT'
                    self.events += ['CROAK', 'RESTART_MUSIC']

    def arm_kill_sprites(self, _keys):
        self.mode = 'FADE_UP'
        self.events.append('RESTART_MUSIC')

    def arm_fade_up(self, _keys):
        self.fade = (self.fade - FADE_STEP) & 0xFF
        self.volume = self.sound_volume if self.volume >= self.sound_volume else self.volume + 1
        if self.fade == 0:
            self.mode = 'DEINIT'

    def arm_deinit(self, _keys):
        self.events.append('QUIT' if self.paused_selection == QUIT_SELECTED else 'RESUMED')
        self.mode = 'NO_PAUSE'

    def shown(self):
        """Sprites alive after the tick: PAUSED and the hidden menu until KILL_SPRITES or Yes."""
        if self.mode not in ('INIT', 'FADE_DOWN', 'MENU'):
            return []
        names = ['PAUSED', 'CONTINUE', 'QUIT']
        if self.menu_mode == 'QUIT':
            names += ['YES', 'NO']
        return names

    def glowing(self):
        """Option_spcore_index's sprite while OptionUpdateSpcores runs (MENU only)."""
        if self.mode != 'MENU':
            return 'NONE'
        if self.menu_mode == 'QUIT':
            return ['YES', 'NO'][self.quit_selection]
        return ['CONTINUE', 'QUIT'][self.selection]

    def row(self):
        return [self.frame, self.mode, self.menu_mode, self.fade, self.volume, self.selection,
                self.quit_selection, self.glowing(), list(self.events)]


class Cheats:
    """Retail's dispatcher 0x0042fda0: the key-down gate and one cursor per sequence."""

    def __init__(self):
        self.cursors = [0] * len(CHEATS)
        self.gate = False

    def check(self, down):
        if not self.gate:
            return []
        self.gate = False
        fired = []
        for i, name in enumerate(CHEAT_NAMES):
            sequence = SEQUENCE[name]
            if sequence[self.cursors[i]] in down:
                self.cursors[i] += 1
                if self.cursors[i] == len(sequence):
                    fired.append(name)
                    self.cursors[i] = 0
            else:
                self.cursors[i] = 0
        return fired


def typed(text):
    """One gated step per character, that key alone down."""
    return [(True, [DIK[c]]) for c in text]


N, O, M, T, X, W, A, Y = DIK['N'], DIK['O'], DIK['M'], DIK['T'], DIK['X'], DIK['W'], DIK['A'], DIK['Y']
CHEAT_TRACES = [
    ('type_lives', typed('NO MORE ROAD SPLATS')),
    ('type_zones', typed('SHOW ME MORE ZONES PLEASE')),
    ('type_levels', typed('WAY TOO HARD FOR THE LIKES OF ME')),
    ('type_timeout', typed('NO MORE TIMEOUT DEATHS PLEASE')),
    ('shared_prefix_parts_at_r_or_t', typed('NO MORE T') + typed('NO MORE R')),
    ('wrong_key_resets', typed('NO MORE RX') + typed('NO MORE ROAD SPLATS')),
    ('wrong_key_is_not_element_zero', typed('NO N') + typed('N')),
    ('held_key_advances', [(True, [N]), (True, [N, O]), (True, [O, SPACE]), (True, [SPACE, M]), (True, [M, X])]),
    ('held_o_in_too', typed('WAY T') + [(True, [O]), (True, [O, X])] + typed(' HARD FOR THE LIKES OF ME')),
    ('stale_gate_resets', typed('NO MO') + [(True, [])] + typed('NO')),
    ('gate_off_ignored', typed('NO') + [(False, [SPACE]), (False, [])] + typed(' MORE ROAD SPLATS')),
    ('two_cheats_in_a_row', typed('NO MORE ROAD SPLATS') + typed('NO MORE ROAD SPLATS')),
]


def cheat_trace(name, steps):
    cheats = Cheats()
    rows = []
    for gate, down in steps:
        if gate:
            cheats.gate = True
        fired = cheats.check(down)
        rows.append({'gate': gate, 'down': list(down), 'cursors': list(cheats.cursors), 'fired': fired})
    return {'name': name, 'steps': rows}


def keyed(start, text):
    """Pause-scene key input: text typed from tick start, one gated key a tick."""
    return {start + i: (True, [DIK[c]]) for i, c in enumerate(text)}


LIVES, ZONES = 'NO MORE ROAD SPLATS', 'SHOW ME MORE ZONES PLEASE'
CHEAT_SCENES = [
    ('cheats_in_menu', 5, True, [
        ({59: ['escape']}, keyed(10, LIVES) | keyed(29, 'NO MORE TIMEOUT DEATHS PLEASE'), 70)]),
    ('cheat_before_menu_events', 5, True, [
        ({28: ['down'], 29: ['fire'], 30: ['fire']}, keyed(10, LIVES) | keyed(31, LIVES), 50)]),
    ('escape_skips_the_check', 5, True, [({10: ['escape']}, {10: (True, [N])}, 12)]),
    ('not_arcade', 5, False, [({}, keyed(10, LIVES), 30)]),
    ('gate_before_menu', 5, True, [({}, {3: (True, [N]), 10: (False, [N]), 11: (False, [O])}, 12)]),
    ('cursors_persist', 5, True, [
        ({20: ['escape']}, keyed(10, ZONES[:10]), 30),
        ({}, keyed(10, ZONES[10:]), 26)]),
    ('stale_gate_on_the_first_menu_tick', 5, True, [
        ({12: ['escape']}, keyed(10, 'NO'), 22),
        ({}, {2: (True, [])}, 11)]),
]


def cheat_scene(name, sound_volume, arcade, pages):
    cheats = Cheats()
    out = []
    for inputs, keys, ticks in pages:
        pause = Pause(sound_volume, cheats, arcade)
        trace = []
        for tick in range(1, ticks + 1):
            gate, down = keys.get(tick, (False, []))
            if gate:
                cheats.gate = True
            pause.tick(inputs.get(tick, []), down)
            trace.append([pause.frame, pause.mode, list(pause.events), list(cheats.cursors), cheats.gate])
        out.append({'inputs': {str(k): v for k, v in sorted(inputs.items())},
                    'keys': {str(k): {'gate': g, 'down': d} for k, (g, d) in sorted(keys.items())},
                    'ticks': ticks, 'trace': trace})
    return {'name': name, 'sound_volume': sound_volume, 'arcade': arcade, 'pages': out}


def read_stack_rows():
    rows = {'arcade': [], 'race': []}
    for row in frontend.read_tsv(frontend.LEVEL_SELECT_TSV):
        if int(row[2]) == -1:
            continue
        rows[row[0]].append({'level': int(row[2]), 'world': int(row[3]), 'stack': int(row[4]), 'theme': int(row[5]),
                             'local': int(row[6]), 'levels_in_world': int(row[7])})
    return rows


def unlock_all_zones(progress):
    """GameCheatModeUnlockAllZones (pause.c:933-965) with GameCheatModeUnlockLevelZone (:1017-1021)."""
    for kind, name in ZONE_UNLOCK:
        level = LEVEL[name]
        if kind == 'assign':
            progress.set_flags(level, frontend.SELECTABLE | frontend.ZONEACCESSIBLE)
        elif not progress.flags_for(level) & frontend.SELECTABLE:
            progress.set_flags(level, frontend.ZONEACCESSIBLE)


def unlock_all_levels(progress):
    """GameCheatModeUnlockAllLevels (pause.c:983-998) over Sel_arcade_levels in order."""
    for row in list(progress.rows['arcade']):
        level = row['level']
        progress.set_flags(level, progress.flags_for(level) | frontend.ZONEACCESSIBLE | frontend.SELECTABLE)


C_FLAG = frontend.COMPLETED
UNLOCK_CASES = [
    ('fresh', []),
    ('first_levels_completed', [('complete', 0), ('complete', 42), ('complete', 36), ('complete', 6),
                                ('set_row', 32, C_FLAG | frontend.SELECTABLE | frontend.ZONEACCESSIBLE),
                                ('complete', 2), ('open_if_closed', 2), ('set_row', 17, C_FLAG)]),
    ('completed_rows', [('complete', 24), ('set_row', 16, C_FLAG), ('set_row', 5, C_FLAG | frontend.SELECTABLE)]),
    ('jungle_rewritten', [('complete', 18)]),
    ('jungle_rewritten_then_completed_cleared', [('complete', 18), ('set_row', 32, C_FLAG)]),
]


def unlock_case(name, setup):
    progress = frontend.Progress(read_stack_rows())
    for op in setup:
        if op[0] == 'complete':
            progress.complete_level(op[1])
        elif op[0] == 'open_if_closed':
            progress.open_level(op[1], 'triangle')
        else:
            progress.rows['arcade'][op[1]]['flags'] = op[2]
    arcade = progress.rows['arcade']
    after_zones, after_levels, after_both = copy.deepcopy(progress), copy.deepcopy(progress), copy.deepcopy(progress)
    unlock_all_zones(after_zones)
    unlock_all_levels(after_levels)
    unlock_all_zones(after_both)
    unlock_all_levels(after_both)
    flags = lambda p: [r['flags'] for r in p.rows['arcade']]
    return {'name': name, 'setup': [list(op) for op in setup], 'levels': [r['level'] for r in arcade],
            'flags': flags(progress), 'race_flags': [r['flags'] for r in progress.rows['race']],
            'after_all_zones': flags(after_zones), 'after_all_levels': flags(after_levels),
            'after_both': flags(after_both)}


def cheats_document():
    for name, _, _, phrase, _, _, sequence in CHEATS:
        if ''.join(LETTER[c] for c in sequence) != phrase:
            raise SystemExit('%s does not spell %s' % (name, phrase))
    rows = read_stack_rows()
    return {
        'source': 'exe 0x0042fda0 (m50_v3_exe_probe.txt leg H3), frogger_cheat_sequences.h, pause.c:900-1021',
        'gate_keys': sorted(DIK.values()),
        'space': SPACE,
        'terminator': CHEAT_END,
        'sequences': [{'cheat': name, 'phrase': phrase, 'source': source, 'file_offset': offset, 'croaks': croaks,
                       'scancodes': sequence}
                      for name, _, offset, phrase, source, croaks, sequence in CHEATS],
        'events': {name: (['CROAK'] if croaks else []) + ['CHEAT_' + name] for name, croaks in CHEAT_CROAKS.items()},
        'traces': [cheat_trace(*trace) for trace in CHEAT_TRACES],
        'scenes': [cheat_scene(*scene) for scene in CHEAT_SCENES],
        'unlock': {'zone_unlock': [[kind, LEVEL[name]] for kind, name in ZONE_UNLOCK],
                   'arcade_rows': rows['arcade'], 'race_rows': rows['race'],
                   'cases': [unlock_case(*case) for case in UNLOCK_CASES]},
    }


def glow(frame):
    return (frame & GLOW_MASK) << GLOW_SHIFT


def sprite_at(name, width):
    return CENTRE_X - (width >> 1) + SIDE[name], CENTRE_Y + RISE[name]


def sprites(pause):
    out = []
    for name in pause.shown():
        image = IMAGES[name][1]
        x, y = sprite_at(name, WIDTHS[image])
        out.append({'sprite': name, 'image': image, 'x': x, 'y': y})
    return out


SCENES = [
    ('resume_by_escape', 5, {12: ['escape']}, 24, [0, 1, 9, 12]),
    ('menu_continue', 12, {10: ['fire']}, 20, [10]),
    ('quit_no', 3, {10: ['down'], 11: ['fire'], 12: ['fire']}, 24, [11]),
    ('quit_yes', 5, {10: ['down'], 12: ['fire'], 14: ['right'], 15: ['fire']}, 18, [14, 15]),
    ('moves_clamp', 4, {10: ['up'], 11: ['down'], 12: ['down'], 13: ['down', 'up'], 14: ['down'],
                        15: ['fire'], 16: ['left'], 17: ['right'], 18: ['right'], 19: ['left', 'right'],
                        20: ['up', 'down'], 21: ['escape', 'right', 'fire']}, 34, [13, 19]),
    ('escape_during_fade', 5, {1: ['escape'], 5: ['escape'], 10: ['escape'], 11: ['escape'],
                               13: ['escape', 'fire']}, 22, []),
    ('volume_from_zero', 0, {10: ['escape']}, 20, []),
]


def run(name, sound_volume, inputs, ticks, sprite_frames):
    for keys in inputs.values():
        for key in keys:
            if key not in BUTTONS:
                raise SystemExit('%s: unknown button %s' % (name, key))
    pause = Pause(sound_volume)
    trace = []
    for tick in range(1, ticks + 1):
        pause.tick(inputs.get(tick, []))
        trace.append(pause.row())
    shots = []
    for frame in sprite_frames:
        shot = Pause(sound_volume)
        for tick in range(1, frame + 1):
            shot.tick(inputs.get(tick, []))
        shots.append({'frame': frame, 'widths': WIDTHS, 'sprites': sprites(shot)})
    return {'name': name, 'sound_volume': sound_volume, 'startup_events': ['HOP'],
            'inputs': {str(k): v for k, v in sorted(inputs.items())}, 'ticks': ticks,
            'trace': trace, 'sprites_at': shots}


def exe_pins():
    """Retail instruction bytes the pause's music rests on: address, bytes and meaning."""
    le32, call, at = level_complete.le32, level_complete.call, level_complete.absolute
    mode = lambda value: 'c705' + at(PAUSE_MODE) + le32(MODES.index(value))
    pins = [
        (GAME_PAUSE + 0x07, '83f8%02x' '57' '55' '0f87' % (len(MODES) - 1) + le32(0x0042f916 - 0x0042f212)
         + 'ff2485' + at(ARM_TABLE),
         'GamePause: Pause_mode 0 to 6 selects an arm from the table at 0x0042f91c'),
        (ARM_TABLE, ''.join(le32(arm) for arm in ARMS),
         'The arms of NO_PAUSE, INIT, FADE_DOWN, MENU, KILL_SPRITES, FADE_UP and DEINIT'),
        (0x0042f33b, mode('FADE_DOWN'), 'INIT: Pause_mode = FADE_DOWN'),
        (0x0042f36e, call(0x0042f36e, PAUSE_CD), 'INIT: PauseCD at 0x00430110 stops the level track'),
        (0x0042f721, '5353' '6a%02x' % CROAK_SOUND + call(0x0042f725, PLAY_SOUND) + '83c410' 'a13c834700' '50'
         + call(0x0042f733, 0x00454080) + '83c404' '891d3c834700' + call(0x0042f741, RESUME_CD)
         + call(0x0042f746, 0x0040d3d0) + call(0x0042f74b, 0x0042fb00) + mode('DEINIT'),
         'MENU, Yes: croak, ResumeCD at 0x00430140, then Pause_mode = DEINIT'),
        (0x0042f7e6, mode('FADE_UP') + call(0x0042f7f0, 0x0040d3d0) + call(0x0042f7f5, RESUME_CD),
         'KILL_SPRITES: Pause_mode = FADE_UP, then ResumeCD'),
        (RESUME_CD, 'a0' + at(level_complete.CD_PRESENT) + '84c0' '7424' 'a1' + at(level_complete.CD_PAUSED)
         + '83f801' '751a' '6a01' 'a1' + at(level_complete.CD_TRACK) + 'c705' + at(level_complete.CD_PAUSED)
         + le32(0) + '50' + call(0x00430165, PLAY_CD),
         'ResumeCD: only when paused, clear the flag and PlayCD(kept track, 1): the track from its start, looping'),
        (0x004300c6, '8935' + at(level_complete.CD_TRACK) + 'c705' + at(level_complete.CD_PLAYING) + le32(1),
         'PlayCD keeps the track it starts for ResumeCD'),
    ]
    return [{'address': '0x%08x' % address, 'bytes_hex': data, 'meaning': meaning}
            for address, data, meaning in pins]


def document():
    return {
        'source': 'pause.c:163-527 GamePause, :559-603 hidden menus, pause.h, OPTIONS.C:381-414',
        'constants': {'fade_step': FADE_STEP, 'fade_end': FADE_END, 'hop_sound': HOP_SOUND,
                      'croak_sound': CROAK_SOUND, 'paused_y': CENTRE_Y + RISE['PAUSED'],
                      'continue_y': CENTRE_Y + RISE['CONTINUE'], 'quit_y': CENTRE_Y + RISE['QUIT'],
                      'yes_no_y': CENTRE_Y + RISE['YES'], 'yes_no_offset': SIDE['YES'],
                      'quit_yes': QUIT_YES, 'quit_no': QUIT_NO,
                      'continue_selected': CONTINUE_SELECTED, 'quit_selected': QUIT_SELECTED},
        'images': {name: image for name, (_text, image) in IMAGES.items()},
        'glow': [[f, glow(f)] for f in (0, 1, 2, 7, 8, 9, 15, 100)],
        'positions': [{'sprite': name, 'width': w, 'x': sprite_at(name, w)[0], 'y': sprite_at(name, w)[1]}
                      for name in SPRITE_ORDER for w in (0, 1, 64, 65)],
        'scenes': [run(*scene) for scene in SCENES],
        'cheats': cheats_document(),
        'exe': {'file': 'FROGGER.EXE', 'image_base': '0x%08x' % level_complete.IMAGE_BASE,
                'text_vma': '0x%08x' % level_complete.TEXT_VMA},
        'exe_pins': exe_pins(),
    }


def dump(value, indent=0):
    """JSON with flat lists and short leaf records on one line, everything else expanded."""
    pad, inner = ' ' * indent, ' ' * (indent + 1)
    line = json.dumps(value, separators=(', ', ': '))
    leaf = isinstance(value, dict) and all(stack.flat(v) for v in value.values()) and len(line) <= 120
    if stack.flat(value) or leaf:
        return line
    if isinstance(value, dict):
        items = [inner + json.dumps(k) + ': ' + dump(v, indent + 1) for k, v in value.items()]
        return '{\n' + ',\n'.join(items) + '\n' + pad + '}'
    return '[\n' + ',\n'.join(inner + dump(v, indent + 1) for v in value) + '\n' + pad + ']'


def strip_c(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    return stack.squash(text)


def play(sound):
    return 'MRSNDPlaySound(%s,NULL,0,0);' % sound


def pause_snippets():
    hop, croak = play('SFX_GEN_FROG_HOP'), play('SFX_GEN_FROG_CROAK')
    centred = '(Game_display_width>>1)-(texture->te_w>>1)'
    s = ['if((!Game_start_timer)&&(!(Game_flags&GAME_FLAG_NO_PAUSE_ALLOWED)))',
         'if((frog->fr_flags&FROG_ACTIVE)&&(MR_CHECK_PAD_PRESSED(frog->fr_input_id,FRR_START))&&',
         'Pause_mode=PAUSE_MODE_INIT;Game_paused_player=frog->fr_input_id;MRSNDKillAllSounds();' + hop,
         'texture=Options_text_textures[%s][Game_language];Game_paused_pause_sprite_ptr=MRCreate2DSprite(%s,'
         'Game_display_height>>1,' % (IMAGES['PAUSED'][0], centred),
         'Game_paused_selection=0;Pause_mode=PAUSE_MODE_FADE_DOWN;Pause_volume=Sound_volume;',
         'poly_f4->r0+=0x%x;poly_f4->g0+=0x%x;poly_f4->b0+=0x%x;' % (FADE_STEP, FADE_STEP, FADE_STEP),
         'if(Pause_volume<1)Pause_volume=0;elsePause_volume--;',
         'if(Pause_poly[0].r0==0x%x){Pause_mode=PAUSE_MODE_MENU;}' % FADE_END,
         'if(MR_CHECK_PAD_PRESSED(Game_paused_player,FRR_START)){Game_paused_selection=0;'
         'Pause_mode=PAUSE_MODE_KILL_SPRITES;' + hop + '}else{',
         'caseHIDDEN_MENU_CONTINUE:if(MR_CHECK_PAD_PRESSED(Game_paused_player,FRR_DOWN)){if(Pause_hidden_selection<'
         '(MAX_HIDDEN_MENU_ITEMS-1)){Pause_hidden_selection++;' + hop + '}}if(MR_CHECK_PAD_PRESSED('
         'Game_paused_player,FRR_UP)){if(Pause_hidden_selection>0){Pause_hidden_selection--;' + hop + '}}'
         'if(MR_CHECK_PAD_RELEASED(Game_paused_player,FRR_CROSS)){switch(Pause_hidden_selection){'
         'caseHIDDEN_MENU_CONTINUE_SELECTED:Game_paused_selection=HIDDEN_MENU_CONTINUE_SELECTED;'
         'Pause_mode=PAUSE_MODE_KILL_SPRITES;' + croak + 'break;caseHIDDEN_MENU_QUIT_SELECTED:'
         'Pause_hidden_menu_mode=HIDDEN_MENU_QUIT;InitialiseHiddenQuitMenu();' + croak + 'break;}}'
         'Option_spcore_index=(Pause_hidden_selection+1);break;',
         'caseHIDDEN_MENU_QUIT:if(MR_CHECK_PAD_PRESSED(Game_paused_player,FRR_LEFT)){if(Pause_hidden_quit_selection<'
         '(MAX_HIDDEN_MENU_QUIT_ITEMS-1)){Pause_hidden_quit_selection++;' + hop + '}}if(MR_CHECK_PAD_PRESSED('
         'Game_paused_player,FRR_RIGHT)){if(Pause_hidden_quit_selection>0){Pause_hidden_quit_selection--;' + hop +
         '}}if(MR_CHECK_PAD_RELEASED(Game_paused_player,FRR_CROSS)){switch(Pause_hidden_quit_selection){'
         'caseHIDDEN_MENU_QUIT_NO:Game_paused_selection=HIDDEN_MENU_CONTINUE_SELECTED;'
         'Pause_mode=PAUSE_MODE_KILL_SPRITES;' + croak + 'break;caseHIDDEN_MENU_QUIT_YES:'
         'Game_paused_selection=HIDDEN_MENU_QUIT_SELECTED;',
         croak + 'MRKill2DSprite(Game_paused_pause_sprite_ptr);Game_paused_pause_sprite_ptr=NULL;'
         'XAControl(XACOM_RESUME,0);OptionClearSpcores();DeInitialiseHiddenMenu();Pause_mode=PAUSE_MODE_DEINIT;'
         'break;}}Option_spcore_index=(Pause_hidden_quit_selection+3);break;}}GamePauseAddPrim();'
         'OptionUpdateSpcores();break;',
         'DeInitialiseHiddenMenu();Pause_mode=PAUSE_MODE_FADE_UP;',
         'poly_f4->r0-=0x%x;poly_f4->g0-=0x%x;poly_f4->b0-=0x%x;' % (FADE_STEP, FADE_STEP, FADE_STEP),
         'if(Pause_volume>=Sound_volume)Pause_volume=Sound_volume;elsePause_volume++;',
         'if(Pause_poly[0].r0==0x00){Pause_mode=PAUSE_MODE_DEINIT;}',
         'if(Game_paused_selection==HIDDEN_MENU_QUIT_SELECTED){Option_page_request=OPTIONS_PAGE_GAME_OVER;',
         'Game_flags&=~GAME_FLAG_PAUSED;Pause_mode=PAUSE_MODE_NO_PAUSE;',
         'poly_f4->r0=0x00;poly_f4->g0=0x00;poly_f4->b0=0x00;',
         'Pause_hidden_quit_selection=HIDDEN_MENU_QUIT_NO;Option_spcore_ptrs[3]=(MR_SP_CORE*)'
         'Game_paused_quit_yes_sprite_ptr;Option_spcore_ptrs[4]=(MR_SP_CORE*)Game_paused_quit_no_sprite_ptr;',
         'Pause_hidden_menu_mode=HIDDEN_MENU_CONTINUE;Pause_hidden_selection=HIDDEN_MENU_CONTINUE_SELECTED;'
         'Option_spcore_ptrs[1]=(MR_SP_CORE*)Game_paused_continue_sprite_ptr;Option_spcore_ptrs[2]=(MR_SP_CORE*)'
         'Game_paused_quit_sprite_ptr;']
    for name, pointer in (('CONTINUE', 'continue'), ('QUIT', 'quit'), ('YES', 'quit_yes'), ('NO', 'quit_no')):
        side = '%+d' % SIDE[name] if SIDE[name] else ''
        s.append('texture=Options_text_textures[%s][Game_language];Game_paused_%s_sprite_ptr=MRCreate2DSprite('
                 '%s%s,(Game_display_height>>1)%+d,' % (IMAGES[name][0], pointer, centred, side, RISE[name]))
    return s


def check_c(c_root):
    """Compare the transcriptions above with the frozen C; returns problems."""
    problems = []
    pause_c = strip_c((c_root / 'pause.c').read_text(encoding='latin-1'))
    for snippet in pause_snippets():
        if snippet not in pause_c:
            problems.append('pause.c no longer contains: %s' % snippet[:100])
    pause_h = strip_c((c_root / 'pause.h').read_text(encoding='latin-1'))
    for snippet in ('enum{HIDDEN_MENU_WAITING,HIDDEN_MENU_CONTINUE,HIDDEN_MENU_QUIT,};',
                    'enum{HIDDEN_MENU_QUIT_YES,HIDDEN_MENU_QUIT_NO,MAX_HIDDEN_MENU_QUIT_ITEMS,};',
                    'enum{HIDDEN_MENU_CONTINUE_SELECTED,HIDDEN_MENU_QUIT_SELECTED,MAX_HIDDEN_MENU_ITEMS,};'):
        if snippet not in pause_h:
            problems.append('pause.h no longer contains: %s' % snippet)
    if [QUIT_YES, QUIT_NO, QUIT_ITEMS, CONTINUE_SELECTED, QUIT_SELECTED, MENU_ITEMS] != [0, 1, 2, 0, 1, 2]:
        problems.append('hidden menu enum values differ from pause.h order')
    options = strip_c((c_root / 'OPTIONS.C').read_text(encoding='latin-1'))
    if 'v=(Option_viewport_ptr->vp_frame_count&0x%x)<<%d;' % (GLOW_MASK, GLOW_SHIFT) not in options:
        problems.append('OPTIONS.C glow differs')
    tempopt = (c_root / 'tempopt.c').read_text(encoding='latin-1')
    for text, image in IMAGES.values():
        match = re.search(r'\{\s*&im_(\w+),[^}]*\},\s*//\s*%s,' % text, tempopt)
        if not match or match.group(1) != image:
            problems.append('tempopt.c %s is not im_%s' % (text, image))
    sound = (c_root / 'sound.h').read_text(encoding='latin-1')
    body = re.search(r'In the GENERIC VAB\.\s*(.*?)\}', sound, flags=re.S)
    generic = re.findall(r'^\s*(SFX_\w+)\s*,', body.group(1), flags=re.M) if body else []
    for name, (value, _froglord) in SOUNDS.items():
        if name not in generic or generic.index(name) != value:
            problems.append('sound.h %s is not %d' % (name, value))
    for snippet in cheat_snippets():
        if snippet not in pause_c:
            problems.append('pause.c no longer contains: %s' % snippet[:100])
    winsys = (c_root / WINSYS_H).read_text(encoding='latin-1')
    if not re.search(r'^\s*//\s*#define\s+PSX_MASTER\b', winsys, flags=re.M) or re.search(
            r'^\s*#define\s+PSX_MASTER\b', winsys, flags=re.M):
        problems.append('PC/winsys.h no longer leaves PSX_MASTER off')
    return problems


def cheat_snippets():
    croak = play('SFX_GEN_FROG_CROAK')
    s = ['if(Sel_mode==SEL_MODE_ARCADE){GameCheatModeCheck();}',
         'MR_VOIDGameCheatModeToggleInfiniteLives(MR_VOID){' + croak + 'if(Cheat_infinite_lives_toggle==TRUE){'
         'DisplayHUDHelp(0,HUD_ITEM_HELP_INFINITE_LIVES_OFF,0,TRUE);',
         'MR_VOIDGameCheatModeUnlockAllZones(MR_VOID){' + croak + 'DisplayHUDHelp(0,HUD_ITEM_HELP_ALL_ZONES_OPEN,0,TRUE);'
         + ''.join('SelectSetLevelFlags(LEVEL_%s,(SEL_LF_ZONEACCESSIBLE|SEL_LF_SELECTABLE));' % name if kind == 'assign'
                   else 'GameCheatModeUnlockLevelZone(LEVEL_%s);' % name for kind, name in ZONE_UNLOCK) + '}',
         'sel_level_info_ptr=Sel_arcade_levels;while(sel_level_info_ptr->li_library_id!=-1){SelectSetLevelFlags('
         'sel_level_info_ptr->li_library_id,SelectGetLevelFlags(sel_level_info_ptr->li_library_id)|'
         'SEL_LF_ZONEACCESSIBLE|SEL_LF_SELECTABLE);sel_level_info_ptr++;}',
         'MR_VOIDGameCheatModeUnlockLevelZone(MR_ULONGlevel_id){if(!(SelectGetLevelFlags(level_id)&SEL_LF_SELECTABLE))'
         'SelectSetLevelFlags(level_id,SEL_LF_ZONEACCESSIBLE);}']
    return s


def check_froggy(engine):
    """Compare the four scancode lists with froggy's exe-pinned header; returns problems."""
    problems = []
    header = (engine / CHEAT_H).read_text(encoding='latin-1')
    header = re.sub(r'/\*.*?\*/', '', header, flags=re.S).replace('\\\n', ' ')
    end = re.search(r'#define FROGGER_CHEAT_SEQ_END\s+0x([0-9A-Fa-f]+)u', header)
    if not end or int(end.group(1), 16) != CHEAT_END:
        problems.append('FROGGER_CHEAT_SEQ_END differs')
    count = re.search(r'#define FROGGER_CHEAT_SEQ_COUNT\s+(\d+)', header)
    if not count or int(count.group(1)) != len(CHEATS):
        problems.append('FROGGER_CHEAT_SEQ_COUNT differs')
    longest = re.search(r'#define FROGGER_CHEAT_SEQ_MAX\s+(\d+)', header)
    if not longest or int(longest.group(1)) != max(len(seq) for seq in SEQUENCE.values()) + 1:
        problems.append('FROGGER_CHEAT_SEQ_MAX differs')
    for name, macro, offset, phrase, _, _, sequence in CHEATS:
        match = re.search(r'#define FROGGER_CHEAT_SEQ_%s_OFF\s+0x([0-9A-Fa-f]+)' % macro, header)
        if not match or int(match.group(1), 16) != offset:
            problems.append('FROGGER_CHEAT_SEQ_%s_OFF differs' % macro)
        match = re.search(r'#define FROGGER_CHEAT_SEQ_%s\s+(.*)' % macro, header)
        elements = [e.strip() for e in match.group(1).split(',')] if match else []
        if not elements or elements[-1] != 'FROGGER_CHEAT_SEQ_END':
            problems.append('FROGGER_CHEAT_SEQ_%s lacks the terminator' % macro)
            continue
        codes = [int(e, 16) for e in elements[:-1]]
        if codes != sequence:
            problems.append('FROGGER_CHEAT_SEQ_%s differs: %s' % (macro, ['0x%02X' % c for c in codes]))
        spelt = ''.join(LETTER.get(c, '?') for c in codes)
        if spelt != phrase:
            problems.append('FROGGER_CHEAT_SEQ_%s spells %r, not %r' % (macro, spelt, phrase))
    listed = re.findall(r'X\((\d), (\w+),\s*FROGGER_CHEAT_SEQ_\w+_OFF,\s*"([^"]*)"\)', header)
    expected = [(str(i), macro, phrase) for i, (_, macro, _, phrase, _, _, _) in enumerate(CHEATS)]
    if listed != expected:
        problems.append('FROGGER_CHEAT_SEQ_LIST differs: %s' % listed)
    return problems


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


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--c-reference', type=Path, default=frontend.DEFAULT_C,
                        help='frozen C source folder (default: ../froggy/engine/vendor/frogger-psx-src/source)')
    parser.add_argument('--froggy-reference', type=Path, default=DEFAULT_FROGGY,
                        help='froggy engine folder (default: ../froggy/engine)')
    parser.add_argument('--data-dir', default=os.environ.get('FROGGER_DATA_DIR', ''),
                        help='retail folder with FROGGER.EXE (default: $FROGGER_DATA_DIR)')
    parser.add_argument('--check', action='store_true', help='compare with the committed file instead of writing')
    args = parser.parse_args()
    problems = check_sound_names()
    if args.c_reference.is_dir():
        c_problems = check_c(args.c_reference)
        problems += c_problems
        if not c_problems:
            print('C cross-check passed against %s' % args.c_reference)
    else:
        print('C source not found at %s; cross-checks skipped' % args.c_reference)
    if args.data_dir:
        exe = game_over.find_exe(Path(args.data_dir))
        if exe is None:
            problems.append('no FROGGER.EXE in %s' % args.data_dir)
        else:
            exe_problems = level_complete.check_exe(exe, exe_pins())
            problems += exe_problems
            if not exe_problems:
                print('Executable pins passed against %s (%d pins)' % (exe, len(exe_pins())))
    else:
        print('FROGGER_DATA_DIR not set; executable pins skipped')
    if (args.froggy_reference / CHEAT_H).is_file():
        froggy_problems = check_froggy(args.froggy_reference)
        problems += froggy_problems
        if not froggy_problems:
            print('froggy cross-check passed against %s' % args.froggy_reference)
    else:
        print('froggy header not found at %s; cross-check skipped' % (args.froggy_reference / CHEAT_H))
    for problem in problems:
        print('cross-check: ' + problem)
    if problems:
        sys.exit(1)
    text = dump(document()) + '\n'
    if args.check:
        old = PAUSE_JSON.read_text(encoding='utf-8') if PAUSE_JSON.exists() else ''
        if old != text:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                       str(PAUSE_JSON), 'generated', n=0))
        print('Committed facts differ from the generator' if old != text else 'Committed facts match the generator')
        sys.exit(1 if old != text else 0)
    PAUSE_JSON.write_text(text, encoding='utf-8')
    print('Wrote %s' % PAUSE_JSON.relative_to(ROOT))


if __name__ == '__main__':
    main()
