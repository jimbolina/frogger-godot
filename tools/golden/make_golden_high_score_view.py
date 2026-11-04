#!/usr/bin/env python3
"""Independent high-score view facts from the frozen C.

Transcribes HSViewStartup, HSViewShutdown, HSViewUpdate and its four level-stack
arms, HSInitialiseScrollyHighScore, HSUpdateScrollyHighScores, HSUpdateFrog and
HSUpdateFlying (HSView.c), the turtle model rotation of LoadOptionsResources
and the camera presets (tempopt.c, tempopt.h), and the letter models of
hsinput.c. The level stack is replayed with the stack model of
make_golden_stack.py and the water projection with the one of
make_golden_options_models.py. Scripted runs replay the page over a synthetic
stack and the scrolly scene over the frozen C's default table. See
tests/golden/specs/frontend.md#high-score-view.
"""
import argparse
import difflib
from pathlib import Path
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden import make_golden_frontend as frontend
from tools.golden import make_golden_options as options
from tools.golden import make_golden_options_models as models
from tools.golden import make_golden_stack as stack

ROOT = frontend.ROOT
VIEW_JSON = frontend.GOLDEN / 'synthetic' / 'frontend_high_score_view.json'

ONE = 0x1000
AFTER_INPUT_DURATION = 4 * 30
LEVEL_DURATION = 3 * 30
FROG_WAIT, FROG_JUMP = 18, 12
FLY_TIME = options.FLYON_TIME
FLY_ON_SPEED, FLY_OFF_SPEED = options.FLYON_SPEED, options.FLYOFF_SPEED
FLY_ON_HEIGHT = options.FLYON_HEIGHT
MODEL_SCALE, LOG_SCALE_X, LOG_TILT = 0x1300, 0x1200, 0x500
FROG_SCALE, FROG_RAISE, THROAT_SCALE = 0x1400, -64, 0x200
TURTLE_ROTATION_Y = 0xc00
TURTLE_POLYS = 12
LOG_POLY_INDICES = [56, 48, 40, 8, 16, 24, 32, 0]
LOG_DIGITS, BLANK_DIGIT = 8, 10
TURTLE_X, PAD_X, LOG_X = -0x480, -0x300, 0x280
ROW_Z0, PITCH = -9 * 0x80, 0x100
SPLASH_SCALE, SPLASH_OT = 10 << 16, -0x8
FOLLOW_OFFSET = 1152
CREEP_STEP, TOUR_WAIT = 20, 10
DISPLAY = stack.DISPLAY
STATUS_END_X, STATUS_WIDTH, PROMPT_Y = stack.STATUS_END_X, stack.STATUS_WIDTH, stack.PROMPT_Y
CAMERAS = {'STATIC': {'source': [0, -3200, -200], 'target': [0, 1024, 50]},
           'MAIN': {'source': [0, -2500, -1280], 'target': [0, 1024, -800]}}
TURTLE_MODEL, LOG_MODEL = 'OPT_TURTLE.XMR', 'HI_LOG.XMR'
LETTER_MODELS = ['HI_%s.XMR' % chr(ord('A') + i) for i in range(26)] + [
    'HI_DOT.XMR', 'OPT_LILLYPAD_BLANK.XMR', 'HI_BACK.XMR', 'HI_END.XMR']
EXTRAS = [('OPT_STAT_BULLRUSH.XMR', -0x400, -0x580), ('OPT_STAT_LILLY.XMR', -0x280, -0x700),
          ('OPT_STAT_LILLY.XMR', 0x300, -0x600), ('OPT_STAT_LILLY.XMR', -0x240, 0x700),
          ('OPT_STAT_BULLRUSH.XMR', 0x200, 0x740)]
DEFAULT_TABLE = [('TIM', 250000), ('M[B', 225000), ('MK[', 200000), ('GCR', 175000), ('JRE', 150000),
                 ('B[S', 125000), ('WIL', 100000), ('JON', 75000), ('DAZ', 50000), ('AL[', 25000)]
SAMPLE_SCORES = [250000, 25000, 7, 0, 99999999, 123456789]
SAMPLE_LETTERS = ['A', 'Z', '[', '.', ' ', '\\', ']', '^']
PORT_FALLBACK_LETTERS = ['a', '-']
LEVEL = frontend.LEVEL
ORIGINAL1, ORIGINAL_MULTI = LEVEL['ORIGINAL1'], LEVEL['ORIGINAL_MULTI_PLAYER']
JUNGLE1, JUNGLE2 = LEVEL['JUNGLE1'], LEVEL['JUNGLE2']
EVENTS = ['hop', 'croak', 'splash', 'spin_out', 'spin_in', 'switched', 'back', 'back_to_options', 'timeout',
          'leave']
HELD, PRESSED = ('up', 'down'), ('left', 'right', 'fire', 'back')
ACTIONS = {'wait2': 'GEN_FROG_WAIT2', 'wait1': 'GEN_FROG_WAIT1', 'hop': 'GEN_FROG_HOP'}


def letter_index(character):
    """HSInitialiseScrollyHighScore's model choice: '.' the dot, ' ' the blank pad, else letter - 'A'."""
    if character == '.':
        return 26
    if character == ' ':
        return 27
    index = ord(character) - ord('A')
    return index if 0 <= index < len(LETTER_MODELS) else None


def digit_cels(score):
    """The eight log digit cels: leading zeros blank (cel 10) except the last digit."""
    cels, shown = [], False
    for j in range(LOG_DIGITS):
        power = 10 ** (LOG_DIGITS - 1 - j)
        digit = score // power
        score -= digit * power
        if digit == 0 and not shown and j < LOG_DIGITS - 1:
            digit = BLANK_DIGIT
        else:
            shown = True
        cels.append(digit)
    return cels


def log_poly_cels(score):
    cels = [None] * 64
    for j, digit in enumerate(digit_cels(score)):
        for k in range(8):
            cels[LOG_POLY_INDICES[j] + k] = digit
    return cels


def jump_lift(count):
    half = FROG_JUMP >> 1
    return (-8 << 16) * (half * half - (count - half) * (count - half))


def row_z(rank):
    return ROW_Z0 + (9 - rank) * PITCH


class Scene:
    """The scrolly set: HSInitialiseScrollyHighScore then HSUpdateScrollyHighScores each tick."""

    def __init__(self, table):
        self.turtles = [models.Mat(TURTLE_X, ROW_Z0 + i * PITCH) for i in range(10)]
        self.pads = [models.Mat(PAD_X + (i % 3) * PITCH, row_z(i // 3)) for i in range(30)]
        self.letters = [letter_index(table[i // 3][0][i % 3]) for i in range(30)]
        self.logs = [models.Mat(LOG_X, row_z(i)) for i in range(10)]
        self.digits = [digit_cels(table[i][1]) for i in range(10)]
        self.extras = [models.Mat(x, z) for _name, x, z in EXTRAS]
        start = self.turtles[0].t
        self.grid, self.direction, self.mode, self.count = 0, 'N', 'STATIONARY', FROG_WAIT
        self.pos = [v << 16 for v in start]
        self.frog = models.Mat(start[0], start[2])
        self.frog.t = [self.pos[0] >> 16, (self.pos[1] >> 16) + FROG_RAISE, self.pos[2] >> 16]
        self.target, self.velocity, self.fr_y, self.lift = [0, 0, 0], [0, 0], 0, 0
        self.action, self.action_set = ACTIONS['wait2'], True
        self.fly_on, self.fly_off = FLY_TIME, 0
        self.followed = False
        self.source_z, self.target_z = CAMERAS['MAIN']['source'][2], CAMERAS['MAIN']['target'][2]
        self.splashes, self.visible = [], False
        self.shadow_visible, self.shadow_phase = False, 0

    def start_fly_off(self):
        self.fly_off, self.fly_on = FLY_TIME, 0

    def stop_flying(self):
        self.fly_on = self.fly_off = 0

    def tick(self, t, scrolly):
        events = []
        self.splashes, self.action_set, self.followed = [], False, False
        if scrolly and not self.fly_off and not self.fly_on:
            z = self.frog.t[2] + FOLLOW_OFFSET
            self.source_z = z + CAMERAS['MAIN']['source'][2]
            self.target_z = z + CAMERAS['MAIN']['target'][2]
            self.followed = True
        if self.fly_on:
            self.fly_on -= 1
        if self.fly_off:
            self.fly_off -= 1
            if not self.fly_off:
                events.append('leave')
        scale = models.diag(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE)
        for mats in (self.pads, self.turtles, self.extras):
            models.project(mats, scale, t, self.fly_on, self.fly_off)
        c, s = models.rcos(LOG_TILT), models.rsin(LOG_TILT)
        tilt = [[ONE, 0, 0], [0, c, -s], [0, s, c]]
        models.project(self.logs, models.mul(models.diag(LOG_SCALE_X, MODEL_SCALE, MODEL_SCALE), tilt), t,
                       self.fly_on, self.fly_off)
        self.visible = scrolly
        if scrolly:
            self.update_frog(events)
        return events

    def update_frog(self, events):
        """HSUpdateFrog."""
        if self.mode == 'STATIONARY':
            self.lift = 0
            self.pos[1] = self.turtles[self.grid].t[1] << 16
            self.count -= 1
            if not self.count:
                if self.grid == 9:
                    self.direction = 'S'
                elif self.grid == 0:
                    self.direction = 'N'
                self.grid += 1 if self.direction == 'N' else -1
                self.mode, self.count = 'JUMPING', FROG_JUMP
                self.target = list(self.turtles[self.grid].t)
                self.fr_y = self.pos[1]
                self.velocity = [stack.cdiv((self.target[0] << 16) - self.pos[0], self.count),
                                 stack.cdiv((self.target[2] << 16) - self.pos[2], self.count)]
                self.action, self.action_set = ACTIONS['hop'], True
                events.append('hop')
            m = models.mul(models.diag(FROG_SCALE, FROG_SCALE, FROG_SCALE), self.turtles[self.grid].m)
            if self.direction == 'S':
                m = models.mul([[-ONE, 0, 0], [0, ONE, 0], [0, 0, -ONE]], m)
            self.frog.m = m
        else:
            self.target[1] = self.turtles[self.grid].t[1]
            self.fr_y += stack.cdiv((self.target[1] << 16) - self.fr_y, self.count)
            self.lift = jump_lift(self.count)
            self.pos[1] = self.fr_y + self.lift
            self.pos[0] += self.velocity[0]
            self.pos[2] += self.velocity[1]
            self.count -= 1
            if not self.count:
                self.pos = [v << 16 for v in self.target]
                self.mode, self.count = 'STATIONARY', FROG_WAIT
                self.action, self.action_set = ACTIONS['wait1'], True
                self.splashes.append(self.grid)
                events.append('splash')
        if self.fly_off:
            self.pos[0] -= FLY_OFF_SPEED << 16
            self.target[0] -= FLY_OFF_SPEED
        self.frog.t = [self.pos[0] >> 16, (self.pos[1] >> 16) + FROG_RAISE, self.pos[2] >> 16]
        self.shadow_visible = self.fly_on == 0
        if self.mode == 'JUMPING':
            self.shadow_phase = max(0, min(5, ((FROG_JUMP - self.count) * 6) // FROG_JUMP))
        else:
            self.shadow_phase = 0

    def frog_state(self):
        return {'visible': self.visible, 'translation': list(self.frog.t), 'position': list(self.pos),
                'turtle': self.grid, 'direction': self.direction, 'jumping': self.mode == 'JUMPING',
                'count': self.count, 'lift': self.lift, 'action': self.action, 'action_set': self.action_set,
                'splashes': list(self.splashes), 'shadow_visible': self.shadow_visible,
                'shadow_phase': self.shadow_phase}

    def models_state(self):
        return {'turtles': [m.flat() for m in self.turtles], 'pads': [m.flat() for m in self.pads],
                'logs': [m.flat() for m in self.logs], 'extras': [m.flat() for m in self.extras]}


def org1_row(rows):
    levels = [r['level'] for r in rows]
    return levels.index(ORIGINAL1) if ORIGINAL1 in levels else 0


def advance_camera(sel):
    """HSViewUpdate_MODE_SELECTING_manual's camera half (no glow change)."""
    sel.vel = max(-stack.MAX_VEL, min(stack.MAX_VEL, sel.vel + sel.acc))
    sel.camera_y += sel.vel
    reached = False
    if sel.flag & stack.GOING_DOWN:
        reached = sel.frame_y <= sel.target_y <= sel.camera_y
    elif sel.flag & stack.GOING_UP:
        reached = sel.frame_y >= sel.target_y >= sel.camera_y
    elif sel.flag == stack.STATIONARY:
        reached = True
    sel.frame_y = sel.camera_y
    return reached


def continue_travel(sel, held, reached):
    for flag, key, step in ((stack.GOING_DOWN, 'down', 1), (stack.GOING_UP, 'up', -1)):
        if sel.flag == flag:
            if key not in held:
                sel.flag |= stack.STOPPING
            elif reached:
                if sel.find_target(step):
                    reached = False
                else:
                    sel.flag |= stack.STOPPING
    if sel.flag & stack.STOPPING and reached:
        sel.acc = sel.vel = 0
        sel.flag = stack.STATIONARY
        sel.camera_y = sel.frame_y = sel.target_y


def advance_spin(sel):
    """The SPIN_OUT/SPIN_IN arm of both SHOW_LEVEL_INFO updates; False while held."""
    s = sel.spin
    if s is None or s['mode'] not in (stack.SPIN_OUT, stack.SPIN_IN):
        return False
    sel.interpolate()
    if s['mode'] == stack.SPIN_OUT:
        s['time'] += 1
        if s['time'] > stack.SPIN_TIME:
            s['time'], s['mode'] = stack.SPIN_TIME, stack.SPIN_HOLD
    else:
        s['time'] -= 1
        if s['time'] < 0:
            sel.mode = 0
    local_y = stack.paths.normalised(s['vec_y'])
    local_x = stack.paths.normalised(stack.outer12(local_y, s['vec_roll']))
    local_z = stack.outer12(local_x, local_y)
    s['axes'] = [[stack.s16(v) for v in local_x], [stack.s16(v) for v in local_y], [stack.s16(v) for v in local_z]]
    sel.title_x = sel.status_x + (STATUS_WIDTH >> 1) - (sel.name_width >> 1)
    if sel.mode == 0:
        sel.spin = None
    return True


class Tour:
    """The high-score view page (HSViewStartup/HSViewUpdate), restarting itself on its own requests."""

    def __init__(self, rows, table, from_options, automatic, new_main, new_levels, first_time, name_width):
        self.rows, self.table = rows, table
        self.from_options, self.automatic = from_options, automatic
        self.new_main, self.new = new_main, dict(new_levels)
        self.first_time, self.name_width = first_time, name_width
        self.camera_mode, self.request, self.wait, self.frame = 'STATIC', None, 0, None
        self.startup('LEVEL_SELECT' if from_options or automatic else 'SCROLLY')

    def startup(self, operation):
        self.operation, self.counter = operation, AFTER_INPUT_DURATION
        self.scene = self.selector = None
        self.picked, self.background, self.shown = False, 0, -1
        if operation == 'SCROLLY':
            self.scene = Scene(self.table)
            self.prompt = 'select3' if self.from_options else 'skip_hi_score'
            self.title_visible = False
        else:
            self.selector = stack.Selector(self.rows, org1_row(self.rows), self.first_time, self.name_width)
            self.prompt = 'select1' if self.first_time else 'select5'
            self.title_visible = not self.automatic
        self.arrows = [self.from_options and operation == 'LEVEL_SELECT',
                       self.from_options and operation == 'SCROLLY']

    def flag(self, level):
        return self.new.get(level, 0)

    def tick(self, inputs, t):
        events, self.frame = [], t
        held = [i for i in inputs if i in HELD]
        pressed = [i for i in inputs if i in PRESSED]
        self.switch = None
        if not self.from_options and 'back' in pressed:
            self.request = 'MAIN_MENU'
            events.append('back')
            if self.scene is not None:
                self.scene.stop_flying()
        if self.operation == 'SCROLLY':
            self.scrolly(pressed, t, events)
        elif self.automatic:
            self.automatic_tick(events)
        else:
            self.manual_tick(held, pressed, events)
        if self.switch is not None:
            self.automatic, self.request = False, None
            if 'back' in events:
                events.remove('back')
            self.startup(self.switch)
        return events

    def scrolly(self, pressed, t, events):
        events += self.scene.tick(t, self.camera_mode == 'SCROLLY')
        if self.from_options:
            if 'right' in pressed:
                events += ['hop', 'switched']
                self.switch, self.arrows = 'LEVEL_SELECT', [False, False]
            elif 'back' in pressed:
                events += ['croak', 'back_to_options']
                self.request, self.arrows = 'OPTIONS', [False, False]
                self.scene.stop_flying()
        else:
            if self.counter == 0:
                self.request = 'MAIN_MENU'
                events.append('timeout')
                self.scene.stop_flying()
            self.counter = (self.counter - 1) & 0xffffffff

    def reach_level(self, events):
        sel = self.selector
        events += ['croak', 'spin_out']
        sel.z[sel.work] = stack.SLIDE_DIST
        sel.mode = 1
        sel.enable_spin()
        self.prompt = 'skip_hi_score'
        self.shown = self.rows[sel.work]['level']
        self.counter = LEVEL_DURATION

    def automatic_tick(self, events):
        sel = self.selector
        sel.slide()
        self.background = stack.BG_SPEED >> 1
        if sel.mode == 0:
            self.prompt = 'skip_hi_score'
            if self.flag(ORIGINAL1) == 1 or self.flag(ORIGINAL_MULTI) == 1:
                self.new[ORIGINAL1] = self.new[ORIGINAL_MULTI] = 0
                self.reach_level(events)
            elif not self.picked:
                while True:
                    if not sel.find_target(1):
                        if self.new_main:
                            events.append('switched')
                            self.switch = 'SCROLLY'
                        else:
                            events.append('timeout')
                            self.request = 'MAIN_MENU'
                        return
                    level = self.rows[sel.work]['level']
                    found = self.flag(JUNGLE1) == 1 if level == JUNGLE2 else self.flag(level) == 1
                    if found:
                        break
                self.picked = True
            elif sel.target_y > sel.camera_y:
                sel.camera_y += CREEP_STEP
                sel.frame_y = sel.camera_y
            else:
                self.wait += 1
                if self.wait == TOUR_WAIT:
                    self.reach_level(events)
                    self.picked, self.wait = False, 0
        else:
            if advance_spin(sel):
                if sel.mode == 0:
                    self.prompt, self.shown = 'skip_hi_score', -1
            else:
                if self.counter == 0:
                    events += ['croak', 'spin_in']
                    sel.spin['mode'] = stack.SPIN_IN
                self.counter = (self.counter - 1) & 0xffffffff

    def manual_tick(self, held, pressed, events):
        sel = self.selector
        sel.slide()
        self.background = (self.background + 1) % stack.BG_SPEED
        if sel.mode == 0:
            reached = advance_camera(sel)
            if sel.flag & stack.STATIONARY:
                if 'down' in held:
                    events.append('hop')
                    if sel.find_target(1):
                        sel.flag, sel.acc, reached = stack.GOING_DOWN, stack.ACC, False
                    else:
                        events.append('croak')
                elif 'up' in held:
                    events.append('hop')
                    if sel.find_target(-1):
                        sel.flag, sel.acc, reached = stack.GOING_UP, -stack.ACC, False
                    else:
                        events.append('croak')
                elif 'left' in pressed:
                    events += ['hop', 'switched']
                    self.switch, self.arrows = 'SCROLLY', [False, False]
                elif 'fire' in pressed:
                    if sel.z[sel.work] == stack.SLIDE_DIST:
                        events += ['croak', 'spin_out']
                        sel.mode = 1
                        sel.enable_spin()
                        self.prompt = 'select3'
                        self.shown = self.rows[sel.work]['level']
                        return
                elif 'back' in pressed:
                    events += ['croak', 'back_to_options']
                    self.request, self.arrows = 'OPTIONS', [False, False]
            continue_travel(sel, held, reached)
        else:
            if advance_spin(sel):
                if sel.mode == 0:
                    self.prompt, self.shown = 'select1', -1
            elif 'back' in pressed:
                events += ['croak', 'spin_in']
                sel.spin['mode'] = stack.SPIN_IN
            elif 'left' in pressed:
                events += ['hop', 'switched']
                self.switch, self.arrows = 'SCROLLY', [False, False]

    def state(self, tick, inputs, events):
        record = {'tick': tick, 'frame': self.frame, 'input': inputs, 'events': events,
                  'operation': self.operation, 'camera_mode': self.camera_mode, 'request': self.request,
                  'counter': self.counter, 'tour_wait': self.wait, 'picked': self.picked, 'prompt': self.prompt,
                  'arrows': list(self.arrows), 'title_visible': self.title_visible,
                  'background': self.background, 'shown_level': self.shown, 'stack': None, 'scene': None}
        if self.selector is not None:
            sel = self.selector
            spin = None
            if sel.spin is not None:
                s = sel.spin
                spin = {'mode': stack.SPIN_NAMES[s['mode']], 'time': s['time'], 'pos': s['pos'],
                        'status_x': sel.status_x}
            record['stack'] = {'mode': stack.MODES[sel.mode], 'camera_y': sel.camera_y, 'camera_vel': sel.vel,
                               'camera_acc': sel.acc, 'camera_flags': sel.flag, 'target_y': sel.target_y,
                               'work_row': sel.work, 'current_z': list(sel.z), 'spin': spin}
        if self.scene is not None:
            record['scene'] = {'fly_on': self.scene.fly_on, 'fly_off': self.scene.fly_off,
                               'frog_visible': self.scene.visible}
        return record


def tour_rows(spec):
    rows = []
    for world, (theme, levels, flags) in enumerate(spec):
        for local, (level, f) in enumerate(zip(levels, flags)):
            rows.append({'world': world, 'theme': theme, 'local': local, 'levels_in_world': len(levels),
                         'flags': f, 'level': level})
    return rows


C, S, Z = frontend.COMPLETED, frontend.SELECTABLE, frontend.ZONEACCESSIBLE
TOUR_STACK = [(5, [24, 25, 26], [C | S | Z, S | Z, Z]), (9, [48, 49], [S | Z, Z]), (3, [12], [S | Z]),
              (4, [19, 20], [S | Z, Z])]
TOUR_SCENARIOS = [
    {'name': 'automatic_tour_then_scrolly',
     'description': 'After entry: the ORIGINAL1 row spins out first for its multiplayer flag, the tour skips '
                    'the locked row 49 that also has a flag and walks to FOR1 (camera 20 a tick, 10 ticks '
                    'wait, spin, 90 held, spin in), then finds no more and, with a new main score, restarts '
                    'as the scrolly table with the static camera, which times out to the main menu.',
     'from_options': False, 'automatic': True, 'new_main': True, 'new_levels': {29: 1, 49: 1, 12: 1},
     'first_time': True, 'frame_start': 100, 'inputs': [[600, []]]},
    {'name': 'automatic_tour_jungle_flag_no_main',
     'description': 'After entry with no new main score: the rewritten jungle row (level 19) is visited for '
                    'the JUNGLE1 flag; the camera passes four rows; the tour then goes straight to the main '
                    'menu. FIRE, LEFT and RIGHT are ignored.',
     'from_options': False, 'automatic': True, 'new_main': False, 'new_levels': {JUNGLE1: 1},
     'first_time': False, 'frame_start': 7, 'inputs': [[30, ['fire']], [20, ['left', 'right']], [300, []]]},
    {'name': 'automatic_tour_back',
     'description': 'After entry, TRIANGLE while the camera travels leaves for the main menu at once.',
     'from_options': False, 'automatic': True, 'new_main': True, 'new_levels': {26: 1, 12: 1},
     'first_time': True, 'frame_start': 0, 'inputs': [[6, []], [1, ['back']], [3, []]]},
    {'name': 'scrolly_after_entry_back',
     'description': 'The scrolly table not from options: models fly on, TRIANGLE leaves for the main menu '
                    'and stops the flying.',
     'from_options': False, 'automatic': False, 'new_main': False, 'new_levels': {},
     'first_time': True, 'frame_start': 50, 'inputs': [[4, []], [1, ['back']], [2, []]]},
    {'name': 'manual_from_options',
     'description': 'From options: hold DOWN through the open rows (HOP, then HOP and CROAK each tick at the '
                    'bottom), UP back, FIRE before and after the box is out, TRIANGLE spins in, LEFT restarts '
                    'as the scrolly table, RIGHT returns to the stack at ORIGINAL1, FIRE then LEFT while the '
                    'level is shown, and TRIANGLE leaves for the options page.',
     'from_options': True, 'automatic': False, 'new_main': False, 'new_levels': {},
     'first_time': False, 'frame_start': 300,
     'inputs': [[2, ['fire']], [8, []], [1, ['fire']], [15, []], [1, ['fire']], [1, ['back']], [12, []],
                [1, ['up']], [60, ['down']], [3, ['down']], [70, ['up']], [10, []], [1, ['left']], [12, []],
                [1, ['left']], [1, ['right']], [9, []], [1, ['fire']], [5, []], [1, ['left']], [8, []],
                [1, ['left']], [3, []], [1, ['back']], [1, []]]},
    {'name': 'manual_back_while_moving',
     'description': 'From options: TRIANGLE while the camera moves is ignored; once stationary it leaves.',
     'from_options': True, 'automatic': False, 'new_main': False, 'new_levels': {},
     'first_time': True, 'frame_start': 0, 'inputs': [[3, ['down']], [1, ['down', 'back']], [25, []],
                                                      [1, ['back']], [2, []]]},
]
SCENE_SCENARIOS = [
    {'name': 'frog_ping_pong',
     'description': 'Main-menu scrolly camera: the models fly on, the frog waits 18 ticks on turtle 0 and hops '
                    'up to turtle 9 and back down to turtle 0, then turns north again; the camera follows its z '
                    'once flying ends.',
     'scrolly': True, 'frame_start': 300, 'inputs': [[600, []]], 'model_ticks': [0, 1, 2, 9, 10, 11, 240]},
    {'name': 'fly_on_then_fly_off',
     'description': 'Main-menu scrolly camera: fly on, the frog takes off, a fly-off starts after tick 25 and '
                    'slides every model and the frog away from x 0 until LEAVE on its tenth tick.',
     'scrolly': True, 'frame_start': 4090, 'inputs': [[24, []], [1, ['fly_off']], [12, []]],
     'model_ticks': [1, 9, 10, 19, 24, 25, 26, 31, 34, 35]},
    {'name': 'static_camera',
     'description': 'High-score view camera: the models fly on and settle; the frog stays hidden and still.',
     'scrolly': False, 'frame_start': 0, 'inputs': [[30, []]], 'model_ticks': [10, 30]},
]


def kept(tick, record, previous):
    """Sampling of long traces: the first 40 ticks, every eighth, and any tick with events or a phase change."""
    if tick <= 40 or tick % 8 == 0 or record['events'] or previous is None:
        return True
    return any(record.get(k) != previous.get(k) for k in PHASE_KEYS) or \
        any((record.get(k) or {}).get('mode') != (previous.get(k) or {}).get('mode') for k in ('stack',)) or \
        ((record.get('stack') or {}).get('spin') or {}).get('mode') != \
        ((previous.get('stack') or {}).get('spin') or {}).get('mode') or \
        (record.get('frog') or {}).get('jumping') != (previous.get('frog') or {}).get('jumping')


PHASE_KEYS = ('operation', 'request', 'picked', 'prompt', 'shown_level', 'arrows', 'fly_on', 'fly_off')


def replay_tour(scenario):
    rows = tour_rows(TOUR_STACK)
    tour = Tour(rows, DEFAULT_TABLE, scenario['from_options'], scenario['automatic'], scenario['new_main'],
                scenario['new_levels'], scenario['first_time'], 96)
    previous = tour.state(0, [], [])
    trace = [previous]
    tick = 0
    for count, inputs in scenario['inputs']:
        for _ in range(count):
            if tour.request is not None:
                return trace, tick
            tick += 1
            events = tour.tick(inputs, scenario['frame_start'] + tick - 1)
            record = tour.state(tick, list(inputs), events)
            if kept(tick, record, previous) or tour.request is not None:
                trace.append(record)
            previous = record
    return trace, tick


def replay_scene(scenario):
    scene = Scene(DEFAULT_TABLE)
    wanted = scenario['model_ticks']

    def state(tick, t, inputs, events):
        record = {'tick': tick, 'frame': t, 'input': inputs, 'events': events, 'fly_on': scene.fly_on,
                  'fly_off': scene.fly_off,
                  'camera': {'followed': scene.followed, 'source_z': scene.source_z, 'target_z': scene.target_z},
                  'frog': scene.frog_state()}
        if tick in wanted:
            record['frog_matrix'] = scene.frog.flat()
            record['models'] = scene.models_state()
        return record

    previous = state(0, None, [], [])
    trace = [previous]
    tick = 0
    for count, inputs in scenario['inputs']:
        for _ in range(count):
            tick += 1
            t = scenario['frame_start'] + tick - 1
            events = scene.tick(t, scenario['scrolly'])
            if 'fly_off' in inputs:
                scene.start_fly_off()
            record = state(tick, t, list(inputs), events)
            if kept(tick, record, previous) or 'models' in record:
                trace.append(record)
            previous = record
    return trace, tick


def document():
    tours = []
    for scenario in TOUR_SCENARIOS:
        trace, ticks = replay_tour(scenario)
        if trace[-1]['request'] is None or trace[-1]['tick'] != ticks:
            sys.exit('tour scenario %s does not leave the page' % scenario['name'])
        out = {k: scenario[k] for k in ('name', 'description', 'from_options', 'automatic', 'new_main',
                                        'first_time', 'frame_start', 'inputs')}
        out['new_levels'] = [[level, flag] for level, flag in sorted(scenario['new_levels'].items())]
        out['ticks'] = ticks
        out['trace'] = trace
        tours.append(out)
    scenes = []
    for scenario in SCENE_SCENARIOS:
        trace, ticks = replay_scene(scenario)
        out = {k: scenario[k] for k in ('name', 'description', 'scrolly', 'frame_start', 'inputs', 'model_ticks')}
        out['ticks'] = ticks
        out['trace'] = trace
        scenes.append(out)
    rows = tour_rows(TOUR_STACK)
    turtles = [{'index': i, 'rank': 10 - i, 'x': TURTLE_X, 'z': ROW_Z0 + i * PITCH, 'cel': 9 - i}
               for i in range(10)]
    pads = [{'index': i, 'rank': i // 3, 'column': i % 3, 'x': PAD_X + (i % 3) * PITCH, 'z': row_z(i // 3)}
            for i in range(30)]
    logs = [{'index': i, 'rank': i, 'x': LOG_X, 'z': row_z(i)} for i in range(10)]
    return {
        'constants': {
            'after_input_duration': AFTER_INPUT_DURATION, 'level_duration': LEVEL_DURATION,
            'frog_wait_time': FROG_WAIT, 'frog_jump_time': FROG_JUMP, 'fly_time': FLY_TIME,
            'fly_on_speed': FLY_ON_SPEED, 'fly_off_speed': FLY_OFF_SPEED, 'fly_on_height': FLY_ON_HEIGHT,
            'model_scale': MODEL_SCALE, 'log_scale_x': LOG_SCALE_X, 'log_tilt': LOG_TILT,
            'frog_scale': FROG_SCALE, 'frog_raise': FROG_RAISE, 'throat_scale': THROAT_SCALE,
            'turtle_model_rotation_y': TURTLE_ROTATION_Y, 'turtle_animated_polys': TURTLE_POLYS,
            'log_poly_indices': LOG_POLY_INDICES, 'log_digits': LOG_DIGITS, 'blank_digit_cel': BLANK_DIGIT,
            'splash_scale': SPLASH_SCALE, 'splash_ot_offset': SPLASH_OT, 'follow_offset': FOLLOW_OFFSET,
            'creep_step': CREEP_STEP, 'tour_wait': TOUR_WAIT, 'cameras': CAMERAS,
            'arrows': {'left': [32, (DISPLAY[1] >> 1) - 16], 'right': [DISPLAY[0] - 64, (DISPLAY[1] >> 1) - 16],
                       'left_flipped': True, 'glow': '((vp_frame_count & 0xff) << 4) & 0xff'},
            'prompt': {'scrolly_x': '%d - te_w' % (STATUS_END_X + STATUS_WIDTH - 16),
                       'stack_x': '%d - te_w' % (STATUS_END_X + STATUS_WIDTH), 'y': PROMPT_Y},
            'start_action': ACTIONS['wait2'], 'frog_update_period': 2},
        'models': {'turtle': TURTLE_MODEL, 'log': LOG_MODEL, 'letters': LETTER_MODELS,
                   'extras': [name for name, _x, _z in EXTRAS]},
        'default_table': [[initials, score] for initials, score in DEFAULT_TABLE],
        'layout': {'turtles': turtles, 'pads': pads, 'logs': logs,
                   'extras': [{'model': name, 'x': x, 'z': z} for name, x, z in EXTRAS],
                   'pad_letters': Scene(DEFAULT_TABLE).letters},
        'log_cels': [{'score': s, 'digits': digit_cels(s), 'polys': log_poly_cels(s)} for s in SAMPLE_SCORES],
        'letter_indices': [[c, letter_index(c)] for c in SAMPLE_LETTERS],
        'port_fallback_letters': [[c, 27] for c in PORT_FALLBACK_LETTERS],
        'frog_motion': [{'count': c, 'lift': jump_lift(c)} for c in range(FROG_JUMP, 0, -1)],
        'arrow_glow': [[f, ((f & 0xff) << 4) & 0xff] for f in (0, 1, 15, 16, 255, 256, 1000)],
        'events': EVENTS,
        'tour_stack': [{k: r[k] for k in ('level', 'world', 'theme', 'local', 'levels_in_world', 'flags')}
                       for r in rows],
        'tour_name_width': 96,
        'tour_scenarios': tours,
        'scene_scenarios': scenes,
    }


def check_c(c_root):
    """Compare the transcriptions above with the frozen C; returns problems."""
    problems = []
    h = (c_root / 'HSView.h').read_text(encoding='latin-1')
    for name, value in (('HIGH_SCORE_AFTER_INPUT_DURATION', '(4*30)'), ('HIGH_SCORE_VIEW_LEVEL_DURATION', '(3*30)'),
                        ('HIGH_SCORE_VIEW_FROG_WAIT_TIME', '18'), ('HIGH_SCORE_VIEW_FROG_JUMP_TIME', '12'),
                        ('HIGH_SCORE_VIEW_NUM_EXTRAS', '5')):
        if stack.define(h, name) != value:
            problems.append('HSView.h %s is %s, transcribed %s' % (name, stack.define(h, name), value))
    if not re.search(r'HIGH_SCORE_OPERATION_MODE_SCROLLY_HIGH_SCORES,\s*HIGH_SCORE_OPERATION_MODE_LEVEL_SELECT,', h) \
            or not re.search(r'HIGH_SCORE_CAMERA_OPERATION_MODE_STATIC,\s*HIGH_SCORE_CAMERA_OPERATION_MODE_SCROLLY,', h):
        problems.append('HSView.h operation or camera mode enums differ')
    t = (c_root / 'tempopt.h').read_text(encoding='latin-1')
    presets = {'MAIN': 'OPTIONS_CAMERA_MAIN', 'STATIC': 'OPTIONS_CAMERA_HS_STATIC'}
    for key, prefix in presets.items():
        for part in ('source', 'target'):
            for axis, value in zip('XYZ', CAMERAS[key][part]):
                name = '%s_%s_OFS_%s' % (prefix, part.upper(), axis)
                if stack.define(t, name) != str(value):
                    problems.append('tempopt.h %s is %s, transcribed %d' % (name, stack.define(t, name), value))
    for name, value in (('OPTIONS_CAMERA_FLYOFF_TIME', '10'), ('OPTIONS_CAMERA_FLYON_TIME', '10'),
                        ('OPTIONS_CAMERA_FLYOFF_SPEED', '0x100'), ('OPTIONS_CAMERA_FLYON_SPEED', '0xa0'),
                        ('OPTIONS_CAMERA_FLYON_HEIGHT', '-((OPTIONS_CAMERA_FLYON_TIME+0)*OPTIONS_CAMERA_FLYON_SPEED)')):
        if stack.define(t, name) != value:
            problems.append('tempopt.h %s differs' % name)
    if stack.define((c_root / 'FROG.H').read_text(encoding='latin-1'), 'FROG_CROAK_MIN_SCALE') != '0x200':
        problems.append('FROG.H FROG_CROAK_MIN_SCALE differs')
    hs_text = (c_root / 'HSView.c').read_text(encoding='latin-1')
    hs = stack.squash(hs_text)
    table = ''.join("{%s,0,%d}," % (','.join("'%s'" % c if c != '[' else "'Z'+1" for c in initials), score)
                    for initials, score in DEFAULT_TABLE)
    release = stack.squash(re.sub(r'#ifdef\s*DEBUG.*?#else(.*?)#endif', r'\1', hs_text, flags=re.S))
    if 'HIGH_SCORE_ENTRYGame_high_score[10]={' + table + '};' not in \
            release.replace('//InitialsScore', ''):
        problems.append('HSView.c Game_high_score defaults differ')
    extras = ''.join('%s,%s,' % (models.hexed(x), models.hexed(z)) for _n, x, z in EXTRAS)
    snippets = [
        'MR_LONGHigh_score_view_extras_coords[]={' + extras + '};',
        'MR_ULONGHigh_score_view_extras_resource_id[]={' + ''.join(
            'RES_%s,' % n.replace('.', '_') for n, _x, _z in EXTRAS) + '};',
        'MR_USHORTHigh_score_log_animated_poly_indices[]={%s};' % ','.join(str(v) for v in LOG_POLY_INDICES),
        'High_score_view_extras_matrix_ptr[i]->t[1]=OPTIONS_CAMERA_FLYON_HEIGHT;',
        'High_score_view_number_matrix_ptr[i]->t[0]=-0x480;'
        'High_score_view_number_matrix_ptr[i]->t[1]=OPTIONS_CAMERA_FLYON_HEIGHT;'
        'High_score_view_number_matrix_ptr[i]->t[2]=(-9*0x80)+(i*0x100);',
        'High_score_view_number_anim_env_ptr[i]=MRAnimEnvFlipbookCreateWhole(MR_GET_RESOURCE_ADDR(RES_OPT_TURTLE_XMR),',
        'for(j=0;j<12;j++)MRMeshAnimatedPolySetCel(mesh_ptr,j,9-i);',
        'High_score_view_frog_anim_env_ptr->ae_flags|=MR_ANIM_ENV_ONE_SHOT;'
        '//SetadefaultanimationactionMRAnimEnvSingleSetAction(High_score_view_frog_anim_env_ptr,GEN_FROG_WAIT2);'
        'High_score_view_frog_anim_env_ptr->ae_update_period=2;',
        'High_score_view_frog_sack_scale_matrix.m[0][0]=FROG_CROAK_MIN_SCALE;',
        'frog->fr_grid_z=0;//lillythatfrogisonfrog->fr_mode=FROG_MODE_STATIONARY;//waitbeforejumping'
        'frog->fr_count=HIGH_SCORE_VIEW_FROG_WAIT_TIME;//timebeforejumping'
        'frog->fr_pos.vx=High_score_view_number_matrix_ptr[0]->t[0]<<16;',
        'frog->fr_direction=FROG_DIRECTION_N;',
        "if(Game_high_score[i/3].he_initials[i%3]=='.')"
        '{//Getaddressof\'.\'modelinmemoryHigh_score_view_initials_model_ptr[i]=MR_GET_RESOURCE_ADDR('
        'High_score_input_letters_resource_id[26]);}',
        "if(Game_high_score[i/3].he_initials[i%3]=='')"
        "{//Getaddressof''modelinmemoryHigh_score_view_initials_model_ptr[i]=MR_GET_RESOURCE_ADDR("
        'High_score_input_letters_resource_id[27]);}',
        "High_score_input_letters_resource_id[Game_high_score[i/3].he_initials[i%3]-'A']);",
        'High_score_view_initials_matrix_ptr[i]->t[0]=-0x300+((i%3)*0x100);',
        'High_score_view_initials_matrix_ptr[i]->t[2]=(-9*0x80)+((9-(i/3))*0x100);',
        'MR_INIT_MAT(High_score_view_initials_matrix_ptr[i]);High_score_view_log_matrix_ptr[i]->t[0]=0x280;',
        'High_score_view_log_matrix_ptr[i]->t[2]=(-9*0x80)+((9-i)*0x100);',
        'log_score=Game_high_score[i].he_score;l=0;for(j=0;j<8;j++){score_digit=log_score;k=7-j;power=1;'
        'while(k--)power*=10;score_digit/=power;log_score=log_score-(score_digit*power);',
        'if((score_digit==0)&&(l==0)&&(j<7))//Leadingspacescore_digit=10;elsel=1;',
        'for(k=0;k<8;k++)MRMeshAnimatedPolySetCel(High_score_view_log_object_ptr[i]->ob_extra.ob_extra_mesh,'
        'High_score_log_animated_poly_indices[j]+k,score_digit);',
        'High_score_view_flyon_counter=OPTIONS_CAMERA_FLYON_TIME;High_score_view_delayed_request=NULL;',
        'if((High_score_camera_operation_mode==HIGH_SCORE_CAMERA_OPERATION_MODE_SCROLLY)&&'
        '(!High_score_view_flyoff_counter)){if(!High_score_view_flyon_counter){'
        'Cameras[0].ca_current_source_ofs.vz=(Frogs[0].fr_lwtrans->t[2]+1152)+OPTIONS_CAMERA_MAIN_SOURCE_OFS_Z;'
        'Cameras[0].ca_current_target_ofs.vz=(Frogs[0].fr_lwtrans->t[2]+1152)+OPTIONS_CAMERA_MAIN_TARGET_OFS_Z;}}'
        'HSUpdateScrollyCamera();//RiverbedandwaterHSUpdateWater();//Updateflyingon/offHSUpdateFlying();',
        'MRScale_matrix.m[0][0]=0x1300;MRScale_matrix.m[1][1]=0x1300;MRScale_matrix.m[2][2]=0x1300;',
        'HSProjectMatricesOntoWaterSurface(High_score_view_initials_matrix_ptr[0],30,&MRScale_matrix);',
        'HSProjectMatricesOntoWaterSurface(High_score_view_number_matrix_ptr[0],10,&MRScale_matrix);',
        'HSProjectMatricesOntoWaterSurface(High_score_view_extras_matrix_ptr[0],HIGH_SCORE_VIEW_NUM_EXTRAS,'
        '&MRScale_matrix);',
        'cos=rcos(0x500);sin=rsin(0x500);MRRot_matrix_X.m[1][1]=cos;MRRot_matrix_X.m[1][2]=-sin;'
        'MRRot_matrix_X.m[2][1]=sin;MRRot_matrix_X.m[2][2]=cos;',
        'MRScale_matrix.m[0][0]=0x1200;MRMulMatrixABC(&MRScale_matrix,&MRRot_matrix_X,&transform);'
        'HSProjectMatricesOntoWaterSurface(High_score_view_log_matrix_ptr[0],10,&transform);',
        'if(High_score_camera_operation_mode==HIGH_SCORE_CAMERA_OPERATION_MODE_SCROLLY){HSUpdateFrog();',
        'High_score_view_frog_anim_env_ptr->ae_flags&=~MR_ANIM_ENV_DISPLAY;',
        'if(!(--frog->fr_count)){if(frog->fr_grid_z==9)frog->fr_direction=FROG_DIRECTION_S;'
        'elseif(frog->fr_grid_z==0)frog->fr_direction=FROG_DIRECTION_N;'
        'if(frog->fr_direction==FROG_DIRECTION_N)frog->fr_grid_z++;elsefrog->fr_grid_z--;'
        'frog->fr_mode=FROG_MODE_JUMPING;frog->fr_count=HIGH_SCORE_VIEW_FROG_JUMP_TIME;',
        'MRAnimEnvSingleSetAction(High_score_view_frog_anim_env_ptr,GEN_FROG_HOP);'
        '//Playeffectwhenjumping.MRSNDPlaySound(SFX_GEN_FROG_HOP,NULL,0,0);',
        'MR_COPY_MAT(frog->fr_lwtrans,High_score_view_number_matrix_ptr[frog->fr_grid_z]);'
        'MRScale_matrix.m[0][0]=0x1400;MRScale_matrix.m[1][1]=0x1400;MRScale_matrix.m[2][2]=0x1400;'
        'MRMulMatrixABB(&MRScale_matrix,frog->fr_lwtrans);',
        'frog->fr_target_pos.vy=High_score_view_number_matrix_ptr[frog->fr_grid_z]->t[1];'
        'frog->fr_y+=((frog->fr_target_pos.vy<<16)-frog->fr_y)/frog->fr_count;'
        'dy=(-8<<16)*(MR_SQR(HIGH_SCORE_VIEW_FROG_JUMP_TIME>>1)-MR_SQR(frog->fr_count-(HIGH_SCORE_VIEW_FROG_JUMP_TIME>>1)));',
        'frog->fr_mode=FROG_MODE_STATIONARY;frog->fr_count=HIGH_SCORE_VIEW_FROG_WAIT_TIME;'
        'MRAnimEnvSingleSetAction(High_score_view_frog_anim_env_ptr,GEN_FROG_WAIT1);',
        'object_ptr=MRCreate3DSprite((MR_FRAME*)High_score_view_number_matrix_ptr[frog->fr_grid_z],MR_OBJ_STATIC,'
        'High_score_splash_animlist);',
        'object_ptr->ob_extra.ob_extra_sp_core->sc_ot_offset=-0x8;object_ptr->ob_extra.ob_extra_sp_core->sc_scale=10<<16;'
        '//PlayeffectwhenlandingMRSNDPlaySound(SFX_GEN_FROG_SPLASH1,NULL,0,0);',
        'frog->fr_lwtrans->t[1]=(frog->fr_pos.vy>>16)-64;',
        'i=((HIGH_SCORE_VIEW_FROG_JUMP_TIME-frog->fr_count)*6)/HIGH_SCORE_VIEW_FROG_JUMP_TIME;i=MAX(0,MIN(5,i));',
        'if(High_score_view_flyon_counter)High_score_view_flyon_counter--;if(High_score_view_flyoff_counter)'
        '{if(!(--High_score_view_flyoff_counter))Option_page_request=High_score_view_delayed_request;}',
        'MR_SET_SVEC(&Cameras[0].ca_current_source_ofs,OPTIONS_CAMERA_HS_STATIC_SOURCE_OFS_X,',
        'texture=Options_text_textures[OPTION_TEXT_SELECT3][Game_language];HSView_user_prompt_sprite_ptr='
        'MRCreate2DSprite(SEL_STATUS_END_X_POS+SEL_STATUS_WIDTH-texture->te_w-16,SEL_PROMPT_SPRITE_Y,',
        'texture=Options_text_textures[OPTION_TEXT_SKIP_HI_SCORE][Game_language];HSView_user_prompt_sprite_ptr='
        'MRCreate2DSprite(SEL_STATUS_END_X_POS+SEL_STATUS_WIDTH-texture->te_w-16,SEL_PROMPT_SPRITE_Y,',
        'Sel_arcade_level_ptr=SelectGetLevelPointer(LEVEL_ORIGINAL1);',
        'High_score_view_automatic_picked_flag=FALSE;SelectLevelStartup();if((From_options==TRUE)||'
        '(HSView_automatic_flag==TRUE)){//Weareshowingalevelstack-inittiledbackgroundSelectLevelCreateBG();}',
        'HSView_arrow_sprite_ptr[0]=sprite=MRCreate2DSprite(32,(Game_display_height>>1)-16,Option_viewport_ptr,'
        '&im_opt_arrow,NULL);sprite->sp_core.sc_flags|=MR_SPF_HORIZONTAL_FLIP;'
        'HSView_arrow_sprite_ptr[1]=MRCreate2DSprite(Game_display_width-64,(Game_display_height>>1)-16,',
        'if(High_score_operation_mode==HIGH_SCORE_OPERATION_MODE_SCROLLY_HIGH_SCORES){//Yes...blankleftsprite(0)'
        'HSView_arrow_sprite_ptr[0]->sp_core.sc_flags|=MR_SPF_NO_DISPLAY;}else{',
        'HSView_arrow_sprite_ptr[1]->sp_core.sc_flags|=MR_SPF_NO_DISPLAY;//}}}//SetautoviewcountHSView_counter='
        'HIGH_SCORE_AFTER_INPUT_DURATION;}',
        'High_score_operation_mode=New_high_score_operation_mode;HSView_automatic_flag=FALSE;',
        'if(From_options==FALSE){//No...viewingafterhiscoreinputif(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],'
        'FRR_TRIANGLE)){//Yes...exitnowOption_page_request=OPTIONS_PAGE_MAIN_OPTIONS;OptionsCameraSnapToMain();',
        'HSUpdateScrollyHighScores();//Didwecomefromoptionspage?if(From_options==TRUE){'
        '//Yes...didwepushright?if(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],MRIP_RIGHT)){'
        '//Yes...playsoundMRSNDPlaySound(SFX_GEN_FROG_HOP,NULL,0,0);',
        'New_high_score_operation_mode=HIGH_SCORE_OPERATION_MODE_LEVEL_SELECT;',
        'MRSNDPlaySound(SFX_GEN_FROG_CROAK,NULL,0,0);Sel_requested_play=FALSE;//GobacktooptionsOption_page_request='
        'OPTIONS_PAGE_OPTIONS;OptionsCameraSnapToOptions();',
        'if(!HSView_counter--)//if(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],FR_GO)){//GobacktomainoptionsSel_requested_play'
        '=FALSE;Option_page_request=OPTIONS_PAGE_MAIN_OPTIONS;',
        'SelectUpdateLevelSlide();SelectLevelUpdateBG();//Accordingtomodeofoperationdo...switch(Sel_game_mode)',
        'if((New_high_scores[LEVEL_ORIGINAL1]==1)||(New_high_scores[LEVEL_ORIGINAL_MULTI_PLAYER]==1)){'
        '//Yes...invalidatedataNew_high_scores[LEVEL_ORIGINAL1]=0;New_high_scores[LEVEL_ORIGINAL_MULTI_PLAYER]=0;'
        'HSViewUpdate_MODE_SELECTING_automatic_reached_level();}elseif(High_score_view_automatic_picked_flag==FALSE)',
        'next_level_flag=SelectFindTarget(SEL_FIND_NEXT);',
        'if(New_high_score==1){//Yes...showmainhighscoresNew_high_score_operation_mode='
        'HIGH_SCORE_OPERATION_MODE_SCROLLY_HIGH_SCORES;High_score_camera_operation_mode='
        'HIGH_SCORE_CAMERA_OPERATION_MODE_STATIC;Option_page_request=OPTIONS_PAGE_HIGH_SCORE_VIEW;}',
        'if(Sel_work_level_ptr->li_library_id==LEVEL_JUNGLE2)next_level_flag=-(New_high_scores[LEVEL_JUNGLE1]==1);'
        'elseif(New_high_scores[Sel_work_level_ptr->li_library_id]==1)',
        'High_score_view_automatic_picked_flag=TRUE;}else{if(Sel_target_y>Sel_camera_y){'
        '//SetcamerapositiontotargetpositionSel_camera_y+=20;Sel_camera_frame->fr_matrix.t[1]=Sel_camera_y;}'
        'else{if(++HSView_automatic_counter==10){HSViewUpdate_MODE_SELECTING_automatic_reached_level();'
        'High_score_view_automatic_picked_flag=FALSE;HSView_automatic_counter=0;}}}',
        'level_ptr=Sel_work_level_ptr;level_ptr->li_current_z=SEL_LEVEL_SLIDE_DIST;Sel_game_mode='
        'SEL_GAME_MODE_SHOW_LEVEL_INFO;SelectEnableSpinMOF(level_ptr);',
        'HSView_counter=HIGH_SCORE_VIEW_LEVEL_DURATION;',
        'if(!HSView_counter--){//Yes...playsoundMRSNDPlaySound(SFX_GEN_FROG_CROAK,NULL,0,0);'
        '//BacktolevelstackSel_spin_mode=SEL_SPIN_IN;}',
        'if(MR_CHECK_PAD_HELD(Frog_input_ports[0],MRIP_DOWN)){//Yes...playsoundMRSNDPlaySound(SFX_GEN_FROG_HOP,NULL,0,0);'
        'if(SelectFindTarget(SEL_FIND_NEXT)==TRUE){Sel_camera_flag=SEL_CAMERA_GOING_DOWN;Sel_camera_acc=SEL_CAMERA_ACC;'
        'reached_target=FALSE;}else{//DMA:Notargetbelowus..perhapsasoundeffecthere?//Yes...playsound'
        'MRSNDPlaySound(SFX_GEN_FROG_CROAK,NULL,0,0);}}',
        'if((Sel_camera_frame->fr_matrix.t[1]<=Sel_target_y)&&(Sel_camera_y>=Sel_target_y))reached_target=TRUE;',
        'if(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],MRIP_LEFT)){if(Sel_mode==SEL_MODE_ARCADE){'
        '//Yes...playsoundMRSNDPlaySound(SFX_GEN_FROG_HOP,NULL,0,0);New_high_score_operation_mode='
        'HIGH_SCORE_OPERATION_MODE_SCROLLY_HIGH_SCORES;Option_page_request=OPTIONS_PAGE_HIGH_SCORE_VIEW;',
        'if(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],FRR_CROSS)){level_ptr=Sel_work_level_ptr;'
        'if(level_ptr->li_current_z==SEL_LEVEL_SLIDE_DIST)',
        'Sel_level_title->sp_core.sc_flags&=~MR_SPF_NO_DISPLAY;texture=Options_text_textures[OPTION_TEXT_SELECT3]'
        '[Game_language];MRChangeSprite(Sel_user_prompt,texture);',
        'if(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],FRR_TRIANGLE|FRR_START))',
        'SelectDisableSpinMOF();texture=Options_text_textures[OPTION_TEXT_SELECT1][Game_language];',
        'elseif(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],FRR_TRIANGLE)){//Yes...playsound'
        'MRSNDPlaySound(SFX_GEN_FROG_CROAK,NULL,0,0);//BacktolevelstackSel_spin_mode=SEL_SPIN_IN;}'
        'elseif(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],MRIP_LEFT))',
        'HSView_arrow_sprite_ptr[0]->sp_core.sc_base_colour.r=(Option_viewport_ptr->vp_frame_count&0xff)<<4;',
    ]
    for snippet in snippets:
        if stack.squash(snippet) not in hs:
            problems.append('HSView.c no longer contains: %s' % snippet[:90])
    tempopt = stack.squash((c_root / 'tempopt.c').read_text(encoding='latin-1'))
    for snippet in ('cos=rcos(0xc00);sin=rsin(0xc00);MRRot_matrix_Y.m[0][0]=cos;MRRot_matrix_Y.m[0][2]=sin;'
                    'MRRot_matrix_Y.m[2][0]=-sin;MRRot_matrix_Y.m[2][2]=cos;'
                    'MRRotateMOF(MR_GET_RESOURCE_ADDR(RES_OPT_TURTLE_XMR),&MRRot_matrix_Y);',
                    'HSInitialiseScrollyHighScore();High_score_camera_operation_mode='
                    'HIGH_SCORE_CAMERA_OPERATION_MODE_SCROLLY;',
                    'camera->ca_move_timer=0;High_score_view_flyoff_counter=0;High_score_view_flyon_counter=0;',
                    'High_score_view_flyoff_counter=OPTIONS_CAMERA_FLYOFF_TIME;High_score_view_flyon_counter=0;'):
        if stack.squash(snippet) not in tempopt:
            problems.append('tempopt.c no longer contains: %s' % snippet[:90])
    hsinput = stack.squash((c_root / 'hsinput.c').read_text(encoding='latin-1'))
    letters = 'MR_ULONGHigh_score_input_letters_resource_id[]={' + ''.join(
        'RES_%s,' % n.replace('.', '_') for n in LETTER_MODELS) + '};'
    if letters not in hsinput:
        problems.append('hsinput.c High_score_input_letters_resource_id differs')
    for snippet in ('HSView_automatic_flag=TRUE;High_score_operation_mode=HIGH_SCORE_OPERATION_MODE_LEVEL_SELECT;'
                    'High_score_camera_operation_mode=HIGH_SCORE_CAMERA_OPERATION_MODE_STATIC;From_options=FALSE;',):
        if stack.squash(snippet) not in hsinput:
            problems.append('hsinput.c no longer contains: %s' % snippet[:90])
    library = (c_root / 'LIBRARY.H').read_text(encoding='latin-1')
    names = re.findall(r'^\s*(LEVEL_[A-Z0-9_]+),', library, flags=re.M)
    for name, value in (('LEVEL_ORIGINAL1', ORIGINAL1), ('LEVEL_ORIGINAL_MULTI_PLAYER', ORIGINAL_MULTI),
                        ('LEVEL_JUNGLE1', JUNGLE1), ('LEVEL_JUNGLE2', JUNGLE2)):
        if name not in names or names.index(name) != value:
            problems.append('LIBRARY.H %s is not %d' % (name, value))
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--c-reference', type=Path, default=frontend.DEFAULT_C,
                        help='frozen C source folder (default: ../froggy/engine/vendor/frogger-psx-src/source)')
    parser.add_argument('--check', action='store_true', help='compare with the committed file instead of writing')
    args = parser.parse_args()
    if args.c_reference.is_dir():
        problems = check_c(args.c_reference)
        for problem in problems:
            print('C cross-check: ' + problem)
        if problems:
            sys.exit(1)
        print('C cross-check passed against %s' % args.c_reference)
    else:
        print('C source not found at %s; cross-checks skipped' % args.c_reference)
    text = stack.dump(document()) + '\n'
    if args.check:
        old = VIEW_JSON.read_text(encoding='utf-8') if VIEW_JSON.exists() else ''
        if old != text:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                       str(VIEW_JSON), 'generated', n=0))
        print('Committed facts differ from the generator' if old != text else 'Committed facts match the generator')
        sys.exit(1 if old != text else 0)
    VIEW_JSON.write_text(text, encoding='utf-8')
    print('Wrote %s' % VIEW_JSON.relative_to(ROOT))


if __name__ == '__main__':
    main()
