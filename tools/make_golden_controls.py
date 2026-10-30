#!/usr/bin/env python3
"""Independent retail PC controller-page (page 25) facts and transition traces.

Transcribes the four shipped controller records, the action order, the 83
bindable DirectInput scancodes with their English key names and the page's
sound events from froggy's frogger_page25_tables.h and mr_stub_page25.c,
maps each scancode to a Godot physical key, and replays the page-25 state
machine (device chooser, record turn, key list, capture, exit) over scripted
pressed-key ticks. See tests/golden/specs/frontend.md#controller-page.
"""
import argparse
import difflib
from pathlib import Path
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_golden_frontend as frontend
import make_golden_stack as stack

ROOT = frontend.ROOT
CONTROLS_JSON = frontend.GOLDEN / 'synthetic' / 'frontend_controls.json'
DEFAULT_FROGGY = ROOT.parent / 'froggy' / 'engine'
TABLES_H = Path('asset_pipeline') / 'include' / 'frogger_page25_tables.h'
PAGE_C = Path('mr_stub') / 'src' / 'glue' / 'mr_stub_page25.c'
SOUND_CFG = ROOT / 'third_party' / 'froglord_cfg' / 'sounds' / '1997-11-19-pc-retail.cfg'

RECORD_COUNT = 4
KEY_SLOTS = 9
RECORD_FIELDS = ['device', 'valid'] + ['key%d' % i for i in range(KEY_SLOTS)]
DEVICE_NONE, DEVICE_KEYBOARD, DEVICE_FIRST_JOYSTICK = 0, 1, 2
SLIDE_FRAMES = 16

ACTIONS = [
    ('LEFT', 0), ('RIGHT', 1), ('UP', 2), ('DOWN', 3), ('SUPERJUMP', 4), ('TONGUE', 5),
    ('CROAK', 6), ('CAMERA_CLOCKWISE', 10), ('CAMERA_ANTICLOCKWISE', 11),
]

DEFAULT_RECORDS = [
    (1, 1, [0xCB, 0xCD, 0xC8, 0xD0, 0x1C, 0x9D, 0x36, 0x28, 0x27]),
    (1, 1, [0x12, 0x13, 0x03, 0x11, 0x02, 0x14, 0x0F, 0x04, 0x05]),
    (1, 1, [0x31, 0x32, 0x22, 0x30, 0x21, 0x33, 0x39, 0x23, 0x24]),
    (1, 1, [0x18, 0x19, 0x09, 0x17, 0x08, 0x1A, 0x15, 0x0A, 0x0B]),
]

ESCAPE, RETURN, F1, F2, F3, LEFT, RIGHT = 0x01, 0x1C, 0x3B, 0x3C, 0x3D, 0xCB, 0xCD
PAGE_KEYS = {'ESCAPE': ESCAPE, 'RETURN': RETURN, 'F1': F1, 'F2': F2, 'F3': F3, 'LEFT': LEFT, 'RIGHT': RIGHT}

U, L, R = 'KEY_LOCATION_UNSPECIFIED', 'KEY_LOCATION_LEFT', 'KEY_LOCATION_RIGHT'

SCANCODES = [
    (0x01, 'DIK_ESCAPE', None, 'KEY_ESCAPE', U),
    (0x02, 'DIK_1', '1', 'KEY_1', U), (0x03, 'DIK_2', '2', 'KEY_2', U), (0x04, 'DIK_3', '3', 'KEY_3', U),
    (0x05, 'DIK_4', '4', 'KEY_4', U), (0x06, 'DIK_5', '5', 'KEY_5', U), (0x07, 'DIK_6', '6', 'KEY_6', U),
    (0x08, 'DIK_7', '7', 'KEY_7', U), (0x09, 'DIK_8', '8', 'KEY_8', U), (0x0A, 'DIK_9', '9', 'KEY_9', U),
    (0x0B, 'DIK_0', '0', 'KEY_0', U),
    (0x0C, 'DIK_MINUS', '-', 'KEY_MINUS', U), (0x0D, 'DIK_EQUALS', '=', 'KEY_EQUAL', U),
    (0x0E, 'DIK_BACK', 'BkSpc', 'KEY_BACKSPACE', U), (0x0F, 'DIK_TAB', 'Tab', 'KEY_TAB', U),
    (0x10, 'DIK_Q', 'Q', 'KEY_Q', U), (0x11, 'DIK_W', 'W', 'KEY_W', U), (0x12, 'DIK_E', 'E', 'KEY_E', U),
    (0x13, 'DIK_R', 'R', 'KEY_R', U), (0x14, 'DIK_T', 'T', 'KEY_T', U), (0x15, 'DIK_Y', 'Y', 'KEY_Y', U),
    (0x16, 'DIK_U', 'U', 'KEY_U', U), (0x17, 'DIK_I', 'I', 'KEY_I', U), (0x18, 'DIK_O', 'O', 'KEY_O', U),
    (0x19, 'DIK_P', 'P', 'KEY_P', U),
    (0x1A, 'DIK_LBRACKET', '[', 'KEY_BRACKETLEFT', U), (0x1B, 'DIK_RBRACKET', ']', 'KEY_BRACKETRIGHT', U),
    (0x1C, 'DIK_RETURN', 'Return', 'KEY_ENTER', U), (0x1D, 'DIK_LCONTROL', 'L-Ctrl', 'KEY_CTRL', L),
    (0x1E, 'DIK_A', 'A', 'KEY_A', U), (0x1F, 'DIK_S', 'S', 'KEY_S', U), (0x20, 'DIK_D', 'D', 'KEY_D', U),
    (0x21, 'DIK_F', 'F', 'KEY_F', U), (0x22, 'DIK_G', 'G', 'KEY_G', U), (0x23, 'DIK_H', 'H', 'KEY_H', U),
    (0x24, 'DIK_J', 'J', 'KEY_J', U), (0x25, 'DIK_K', 'K', 'KEY_K', U), (0x26, 'DIK_L', 'L', 'KEY_L', U),
    (0x27, 'DIK_SEMICOLON', ';', 'KEY_SEMICOLON', U), (0x28, 'DIK_APOSTROPHE', "'", 'KEY_APOSTROPHE', U),
    (0x29, 'DIK_GRAVE', '#', 'KEY_QUOTELEFT', U), (0x2A, 'DIK_LSHIFT', 'L-Shift', 'KEY_SHIFT', L),
    (0x2B, 'DIK_BACKSLASH', '\\', 'KEY_BACKSLASH', U),
    (0x2C, 'DIK_Z', 'Z', 'KEY_Z', U), (0x2D, 'DIK_X', 'X', 'KEY_X', U), (0x2E, 'DIK_C', 'C', 'KEY_C', U),
    (0x2F, 'DIK_V', 'V', 'KEY_V', U), (0x30, 'DIK_B', 'B', 'KEY_B', U), (0x31, 'DIK_N', 'N', 'KEY_N', U),
    (0x32, 'DIK_M', 'M', 'KEY_M', U),
    (0x33, 'DIK_COMMA', ',', 'KEY_COMMA', U), (0x34, 'DIK_PERIOD', '.', 'KEY_PERIOD', U),
    (0x35, 'DIK_SLASH', '/', 'KEY_SLASH', U), (0x36, 'DIK_RSHIFT', 'R-Shift', 'KEY_SHIFT', R),
    (0x37, 'DIK_MULTIPLY', '*', 'KEY_KP_MULTIPLY', U), (0x38, 'DIK_LMENU', 'L-Alt', 'KEY_ALT', L),
    (0x39, 'DIK_SPACE', 'Space', 'KEY_SPACE', U), (0x3A, 'DIK_CAPITAL', None, 'KEY_CAPSLOCK', U),
    (0x3B, 'DIK_F1', None, 'KEY_F1', U), (0x3C, 'DIK_F2', None, 'KEY_F2', U), (0x3D, 'DIK_F3', None, 'KEY_F3', U),
    (0x3E, 'DIK_F4', None, 'KEY_F4', U), (0x3F, 'DIK_F5', None, 'KEY_F5', U), (0x40, 'DIK_F6', None, 'KEY_F6', U),
    (0x41, 'DIK_F7', None, 'KEY_F7', U), (0x42, 'DIK_F8', None, 'KEY_F8', U), (0x43, 'DIK_F9', None, 'KEY_F9', U),
    (0x44, 'DIK_F10', None, 'KEY_F10', U), (0x45, 'DIK_NUMLOCK', None, 'KEY_NUMLOCK', U),
    (0x46, 'DIK_SCROLL', None, 'KEY_SCROLLLOCK', U),
    (0x47, 'DIK_NUMPAD7', 'Numpad 7', 'KEY_KP_7', U), (0x48, 'DIK_NUMPAD8', 'Numpad 8', 'KEY_KP_8', U),
    (0x49, 'DIK_NUMPAD9', 'Numpad 9', 'KEY_KP_9', U), (0x4A, 'DIK_SUBTRACT', 'Numpad -', 'KEY_KP_SUBTRACT', U),
    (0x4B, 'DIK_NUMPAD4', 'Numpad 4', 'KEY_KP_4', U), (0x4C, 'DIK_NUMPAD5', 'Numpad 5', 'KEY_KP_5', U),
    (0x4D, 'DIK_NUMPAD6', 'Numpad 6', 'KEY_KP_6', U), (0x4E, 'DIK_ADD', 'Numpad +', 'KEY_KP_ADD', U),
    (0x4F, 'DIK_NUMPAD1', 'Numpad 1', 'KEY_KP_1', U), (0x50, 'DIK_NUMPAD2', 'Numpad 2', 'KEY_KP_2', U),
    (0x51, 'DIK_NUMPAD3', 'Numpad 3', 'KEY_KP_3', U), (0x52, 'DIK_NUMPAD0', 'Numpad 0', 'KEY_KP_0', U),
    (0x53, 'DIK_DECIMAL', 'Numpad .', 'KEY_KP_PERIOD', U),
    (0x57, 'DIK_F11', None, 'KEY_F11', U), (0x58, 'DIK_F12', None, 'KEY_F12', U),
    (0x9C, 'DIK_NUMPADENTER', 'Enter', 'KEY_KP_ENTER', U), (0x9D, 'DIK_RCONTROL', 'R-Ctrl', 'KEY_CTRL', R),
    (0xB5, 'DIK_DIVIDE', 'Numpad /', 'KEY_KP_DIVIDE', U), (0xB7, 'DIK_SYSRQ', None, 'KEY_PRINT', U),
    (0xB8, 'DIK_RMENU', 'R-Alt', 'KEY_ALT', R), (0xC5, 'DIK_PAUSE', None, 'KEY_PAUSE', U),
    (0xC7, 'DIK_HOME', 'Home', 'KEY_HOME', U), (0xC8, 'DIK_UP', 'Up', 'KEY_UP', U),
    (0xC9, 'DIK_PRIOR', 'PgUp', 'KEY_PAGEUP', U), (0xCB, 'DIK_LEFT', 'Left', 'KEY_LEFT', U),
    (0xCD, 'DIK_RIGHT', 'Right', 'KEY_RIGHT', U), (0xCF, 'DIK_END', 'End', 'KEY_END', U),
    (0xD0, 'DIK_DOWN', 'Down', 'KEY_DOWN', U), (0xD1, 'DIK_NEXT', 'PgDown', 'KEY_PAGEDOWN', U),
    (0xD2, 'DIK_INSERT', 'Ins', 'KEY_INSERT', U), (0xD3, 'DIK_DELETE', 'Del', 'KEY_DELETE', U),
    (0xDB, 'DIK_LWIN', None, 'KEY_META', L), (0xDC, 'DIK_RWIN', None, 'KEY_META', R),
    (0xDD, 'DIK_APPS', None, 'KEY_MENU', U),
]
BINDABLE = {code: name for code, _, name, _, _ in SCANCODES if name is not None}
BINDABLE_COUNT = 83

EVENTS = [
    ('refuse_exit', 'SFX_GEN_FROG_CROAK', 'GEN_FROG_CROAK', 'ESC on the chooser while a record is invalid'),
    ('refuse_unnamed', 'SFX_GEN_FROG_CROAK', 'GEN_FROG_CROAK', 'captured scancode has no key name'),
    ('refuse_duplicate', 'SFX_GEN_FROG_CROAK', 'GEN_FROG_CROAK', 'captured scancode is bound to another record or an earlier slot'),
    ('cursor', 'SFX_GEN_FROG_HOP', 'GEN_FROG_HOP', 'LEFT/RIGHT moved the device cursor'),
    ('page', 'SFX_GEN_FROG_SUPER_HOP', 'GEN_FROG_HOP_SUPER', 'F1/F2 changed the record'),
    ('accept', 'SFX_GEN_FROG_HIT_GROUND', 'GEN_FROG_HIT_GROUND', 'a captured key was taken'),
    ('back', 'SFX_GEN_FROG_SLURP', 'GEN_SLURP', 'ESC left the chooser, key list or capture'),
    ('enter', 'SFX_GEN_CLOCK_TICK', 'GEN_CLOCK_TICK', 'RETURN committed a device, or F3/F1 entered a sub-page'),
    ('exit', None, None, 'state 9 finished; the page requests OPTIONS'),
]
SOUND_IDS = {'SFX_GEN_FROG_CROAK': 3, 'SFX_GEN_FROG_HOP': 6, 'SFX_GEN_FROG_SUPER_HOP': 7,
             'SFX_GEN_FROG_HIT_GROUND': 12, 'SFX_GEN_FROG_SLURP': 20, 'SFX_GEN_CLOCK_TICK': 24}

SHOWN_BLANK, SHOWN_PROMPT = -2, -1


def default_array():
    """The 44-value serialised layout of the shipped records."""
    values = []
    for device, valid, keys in DEFAULT_RECORDS:
        values += [device, valid] + list(keys)
    return values


class Page:
    """Page 25's Startup and Update over pressed-key ticks (mr_stub_page25.c)."""

    def __init__(self, values, joysticks=0):
        self.dev = [values[r * 11] for r in range(RECORD_COUNT)]
        self.valid = [values[r * 11 + 1] for r in range(RECORD_COUNT)]
        self.keys = [list(values[r * 11 + 2:r * 11 + 11]) for r in range(RECORD_COUNT)]
        self.attached = joysticks
        self.state, self.a, self.b, self.c = 0, 0, 0, 0
        self.phase, self.counter = 0, 0
        self.record, self.action = 0, 0
        self.cursor = self.dev[0]
        top = DEVICE_KEYBOARD
        for device in range(DEVICE_FIRST_JOYSTICK, DEVICE_FIRST_JOYSTICK + joysticks):
            if self.free(0, device):
                top = device
        self.cursor_max = top
        if self.cursor > self.cursor_max:
            self.cursor = self.cursor_max
        self.scratch = [0] * KEY_SLOTS
        self.shown = [SHOWN_BLANK] * KEY_SLOTS
        self.finished = False
        self.events = []

    def values(self):
        out = []
        for r in range(RECORD_COUNT):
            out += [self.dev[r], self.valid[r]] + self.keys[r]
        return out

    def unique(self, r):
        return 1 if len(set(self.keys[r])) == KEY_SLOTS else 0

    def every_valid(self):
        return all(self.valid)

    def already_bound(self, record, action, code):
        for r in range(RECORD_COUNT):
            bound = action if r == record else KEY_SLOTS
            if code in self.keys[r][:bound]:
                return True
        return False

    def free(self, record, device):
        if device < DEVICE_FIRST_JOYSTICK:
            return True
        if device - DEVICE_FIRST_JOYSTICK >= self.attached:
            return False
        return all(self.dev[r] != device for r in range(RECORD_COUNT) if r != record)

    def step(self, pressed):
        self.events = []
        if self.finished:
            return
        p = set(pressed)
        s = self.state
        if s == 0:
            self.state, self.counter = 4, 0
        elif s == 1:
            self.helper_a(p)
        elif s == 2:
            self.helper_b(p)
        elif s == 3:
            self.helper_c(p)
        elif s == 4:
            self.counter += 1
            if self.counter == SLIDE_FRAMES:
                self.a, self.counter, self.state = 0, 0, 1
        elif s in (5, 6, 7, 8):
            if self.transition():
                if s == 5:
                    self.b, self.state = 0, 2
                elif s == 6:
                    self.a, self.state = 0, 1
                elif s == 7:
                    self.c, self.state = 0, 3
                else:
                    self.b, self.state = 0, 2
        else:
            self.counter += 1
            if self.counter >= SLIDE_FRAMES:
                self.counter = 0
                self.finished = True
                self.events.append('exit')

    def transition(self):
        if self.phase == 0:
            self.counter += 1
            if self.counter == SLIDE_FRAMES:
                self.phase, self.counter = 1, 0
            return False
        self.counter += 1
        if self.counter != SLIDE_FRAMES:
            return False
        self.counter, self.phase = 0, 0
        return True

    def helper_a(self, p):
        if self.a == 0:
            self.a = 1
            return
        if self.a == 1:
            if ESCAPE in p:
                if self.every_valid():
                    self.state, self.phase, self.counter = 9, 0, 0
                    self.events.append('back')
                    return
                self.events.append('refuse_exit')
            if RETURN in p:
                self.dev[self.record] = self.cursor
                self.events.append('enter')
                if self.cursor == DEVICE_KEYBOARD:
                    self.valid[self.record] = self.unique(self.record)
            if F3 in p and self.cursor == DEVICE_KEYBOARD:
                self.state = 5
                self.events.append('enter')
            if LEFT in p and self.cursor != 0:
                self.cursor -= 1
                self.events.append('cursor')
                self.counter, self.a = 0, 3
            if RIGHT in p and self.cursor < self.cursor_max:
                self.cursor += 1
                self.events.append('cursor')
                self.counter, self.a = 0, 2
            if F1 in p and self.record != 0:
                self.record -= 1
                self.events.append('page')
                self.a = 5
            if F2 in p and self.record < 3:
                self.record += 1
                self.events.append('page')
                self.a = 5
            return
        if self.a in (2, 3):
            self.counter += 1
            if self.counter >= SLIDE_FRAMES:
                self.counter = 0
                if not self.free(self.record, self.cursor):
                    self.cursor += 1 if self.a == 2 else -1
                    return
                self.a = 1
            return
        if self.phase == 0:
            self.counter += 1
            if self.counter != SLIDE_FRAMES:
                return
            self.counter, self.phase = 0, 1
            self.cursor = self.dev[self.record]
            if self.cursor == DEVICE_KEYBOARD:
                self.valid[self.record] = self.unique(self.record)
            if not self.free(self.record, self.cursor):
                self.cursor = 0
                self.dev[self.record] = 0
            return
        self.counter += 1
        if self.counter != SLIDE_FRAMES:
            return
        self.counter, self.phase, self.a = 0, 0, 1

    def helper_b(self, p):
        if self.b == 0:
            self.shown = list(self.keys[self.record])
            self.b = 1
            return
        if ESCAPE in p:
            self.state, self.phase, self.counter = 6, 0, 0
            self.shown = [SHOWN_BLANK] * KEY_SLOTS
            self.events.append('back')
            return
        if F1 in p:
            self.state, self.phase, self.counter = 7, 0, 0
            self.events.append('enter')
            self.shown = [SHOWN_BLANK] * KEY_SLOTS

    def helper_c(self, p):
        if self.c == 0:
            self.action = 0
            self.scratch = list(self.keys[self.record])
            self.c = 1
            self.shown[0] = SHOWN_PROMPT
            return
        if self.c == 1:
            if ESCAPE in p:
                self.state, self.phase, self.counter = 8, 0, 0
                self.keys[self.record] = list(self.scratch)
                self.events.append('back')
                return
            if not p:
                return
            code = min(p)
            if code not in BINDABLE:
                self.events.append('refuse_unnamed')
                return
            if self.already_bound(self.record, self.action, code):
                self.events.append('refuse_duplicate')
                return
            self.keys[self.record][self.action] = code
            self.shown[self.action] = code
            self.events.append('accept')
            self.phase, self.counter, self.c = 0, 0, 2
            return
        if self.phase == 0:
            self.counter += 1
            if self.counter != SLIDE_FRAMES:
                return
            self.counter, self.phase = 0, 1
            if self.action != KEY_SLOTS - 1:
                self.shown[self.action + 1] = SHOWN_PROMPT
            return
        self.counter += 1
        if self.counter != SLIDE_FRAMES:
            return
        self.counter, self.phase = 0, 0
        self.action += 1
        if self.action == KEY_SLOTS:
            self.valid[self.record] = self.unique(self.record)
            self.state, self.phase, self.counter = 8, 0, 0
            return
        self.c = 1


def idle(n):
    return [n, []]


def press(*codes):
    return [1, list(codes)]


def with_records(changes):
    values = default_array()
    for record, field, value in changes:
        values[record * 11 + RECORD_FIELDS.index(field)] = value
    return values


WAIT_CHOOSER = idle(20)
SETTLE = idle(34)


def rebind_inputs(codes):
    out = []
    for code in codes:
        out += [press(code), idle(33)]
    return out


SCENARIOS = [
    ('enter_and_exit', 'startup 0 -> 4 -> 1, ESC with every record valid slides out and exits', 0, None,
     [WAIT_CHOOSER, press(ESCAPE), idle(17)]),
    ('device_carousel', 'LEFT to none, LEFT clamped, RETURN commits none, F3 ignored off the keyboard, '
     'RIGHT back, RIGHT clamped at the highest free device, RETURN re-derives valid', 0, None,
     [WAIT_CHOOSER, press(LEFT), idle(17), press(LEFT), idle(2), press(RETURN), idle(1), press(F3), idle(2),
      press(RIGHT), idle(17), press(RIGHT), idle(1), press(RETURN), idle(1), press(ESCAPE), idle(17)]),
    ('record_paging', 'F1 clamped at record 0, F2 to records 1-3 with the record turn, F2 clamped at 3, F1 back; '
     'record 2 carries an unattached joystick and loses it at the turn; record 1 is invalid but unique and '
     'the turn re-derives it', 0,
     [(2, 'device', 2), (1, 'valid', 0)],
     [WAIT_CHOOSER, press(ESCAPE), idle(1), press(F1), idle(2), press(F2), idle(33), press(F2), idle(33),
      press(F2), idle(33), press(F2), idle(2), press(F1), idle(33), press(ESCAPE), idle(17)]),
    ('rebind_all_with_refusals', 'F3 to the key list, F1 to capture; unnamed F4 and ESC-free refusals, '
     'same key on its own slot accepted, another record\'s key and an earlier slot\'s key refused, '
     'two keys on one tick take the lowest scancode, all nine slots captured, back out and exit', 0, None,
     [WAIT_CHOOSER, press(F3), idle(40), press(F1), idle(40),
      press(0x3E), idle(1), press(LEFT), idle(33),
      press(0x12), idle(1), press(LEFT), idle(1), press(0x1F, 0x1E), idle(33)]
     + rebind_inputs([0x20, 0x25, 0x26, 0x1D, 0x2A, 0x10, 0x2C])
     + [idle(40), press(ESCAPE), idle(40), press(ESCAPE), idle(17)]),
    ('capture_escape_undo', 'record 3: capture two keys then ESC restores all nine; the key list redraws them',
     0, None,
     [WAIT_CHOOSER, press(F2), idle(33), press(F2), idle(33), press(F2), idle(33), press(F3), idle(40),
      press(F1), idle(40), press(0x1E), idle(33), press(0x1F), idle(33), press(ESCAPE), idle(40),
      press(ESCAPE), idle(40), press(ESCAPE), idle(17)]),
    ('exit_refused_until_valid', 'record 1 holds a duplicate and is invalid: ESC croaks; paging keeps it '
     'invalid; recapturing record 1 makes it valid and ESC exits', 0,
     [(1, 'valid', 0), (1, 'key1', 0x12)],
     [WAIT_CHOOSER, press(ESCAPE), idle(1), press(F2), idle(33), press(ESCAPE), idle(1), press(F3), idle(40),
      press(F1), idle(40)]
     + rebind_inputs([0x10, 0x11, 0x12, 0x13, 0x14, 0x16, 0x1E, 0x1F, 0x20])
     + [idle(40), press(ESCAPE), idle(40), press(ESCAPE), idle(17)]),
    ('joystick_choice', 'one attached joystick: RIGHT reaches device 2, RETURN commits it, F3 is keyboard only',
     1, None,
     [WAIT_CHOOSER, press(RIGHT), idle(17), press(RIGHT), idle(17), press(RETURN), idle(1), press(F3), idle(2),
      press(LEFT), idle(17), press(RETURN), idle(1), press(ESCAPE), idle(17)]),
]


def snapshot(page, tick, pressed, last):
    row = {'tick': tick, 'pressed': sorted(pressed), 'state': page.state, 'helper_a': page.a,
           'helper_b': page.b, 'helper_c': page.c, 'phase': page.phase, 'counter': page.counter,
           'record': page.record, 'cursor': page.cursor, 'action': page.action,
           'finished': page.finished, 'events': list(page.events)}
    values = page.values()
    if last is None or values != last[0]:
        row['bindings'] = values
    if last is None or page.shown != last[1]:
        row['shown'] = list(page.shown)
    return row, (values, list(page.shown))


def run(name, description, joysticks, changes, inputs):
    initial = with_records(changes) if changes else default_array()
    page = Page(initial, joysticks)
    trace = []
    row, last = snapshot(page, 0, [], None)
    trace.append(row)
    tick = 0
    for count, codes in inputs:
        for _ in range(count):
            tick += 1
            page.step(codes)
            row, last = snapshot(page, tick, codes, last)
            trace.append(row)
            if page.finished:
                break
        if page.finished:
            break
    if not page.finished:
        sys.exit('scenario %s does not reach the exit' % name)
    return {'name': name, 'description': description, 'joysticks': joysticks, 'initial': initial,
            'inputs': inputs, 'trace': trace}


def scancode_rows():
    rows = []
    for code, dik, name, key, location in SCANCODES:
        rows.append({'scancode': code, 'dik': dik, 'bindable': name is not None, 'name': name,
                     'godot_key': key, 'location': location})
    return rows


def document():
    if len(BINDABLE) != BINDABLE_COUNT:
        sys.exit('expected %d bindable scancodes, found %d' % (BINDABLE_COUNT, len(BINDABLE)))
    physical = [(key, location) for _, _, _, key, location in SCANCODES]
    if len(set(physical)) != len(physical):
        sys.exit('two scancodes share a Godot key and location')
    defaults = default_array()
    every_key = [k for _, _, keys in DEFAULT_RECORDS for k in keys]
    if len(set(every_key)) != len(every_key) or not all(k in BINDABLE for k in every_key):
        sys.exit('shipped defaults are not unique bindable keys')
    return {
        'source': 'froggy engine/asset_pipeline/include/frogger_page25_tables.h and '
                  'engine/mr_stub/src/glue/mr_stub_page25.c (retail page 25, Startup 0x0043AF20, '
                  'Update 0x0043C260)',
        'layout': {'record_count': RECORD_COUNT, 'key_slots': KEY_SLOTS, 'record_fields': RECORD_FIELDS,
                   'record_stride': len(RECORD_FIELDS), 'length': RECORD_COUNT * len(RECORD_FIELDS)},
        'devices': {'none': DEVICE_NONE, 'keyboard': DEVICE_KEYBOARD, 'first_joystick': DEVICE_FIRST_JOYSTICK},
        'actions': [{'slot': i, 'name': n, 'vendored_index': v} for i, (n, v) in enumerate(ACTIONS)],
        'defaults': [{'record': r, 'device': d, 'valid': v, 'keys': k} for r, (d, v, k) in enumerate(DEFAULT_RECORDS)],
        'default_array': defaults,
        'page_keys': PAGE_KEYS,
        'bindable_count': BINDABLE_COUNT,
        'scancodes': scancode_rows(),
        'unknown_scancode': 0,
        'rules': {
            'slide_frames': SLIDE_FRAMES,
            'shown_blank': SHOWN_BLANK,
            'shown_prompt': SHOWN_PROMPT,
            'capture_order': 'lowest pressed scancode first; ESC is tested before the scan',
            'refuse_unnamed': 'a scancode outside the bindable set',
            'refuse_duplicate': 'bound in any other record, or in this record at a slot below the one being captured',
            'valid': 'set to whether the nine keys of the record are distinct: on RETURN with the keyboard chosen, '
                     'at the record turn when the record holds the keyboard, and after the ninth capture',
            'exit': 'ESC leaves the chooser only when every record is valid',
            'device_free': 'none and keyboard are always free; joystick d is free when d - 2 is an attached '
                           'joystick no other record holds',
            'cursor_max': 'the highest free device for record 0 at startup, at least the keyboard',
        },
        'events': [{'name': n, 'sound': s, 'sound_id': SOUND_IDS.get(s, -1) if s else -1, 'froglord': f,
                    'meaning': m} for n, s, f, m in EVENTS],
        'scenarios': [run(*scenario) for scenario in SCENARIOS],
    }


def check_froggy(engine):
    problems = []
    tables = (engine / TABLES_H).read_text(encoding='latin-1')
    actions = re.findall(r'X\((\d+),\s*(\d+),\s*"(\w+)"\)', tables)
    if [(n, int(v)) for _, v, n in actions] != ACTIONS:
        problems.append('action list differs: %s' % actions)
    records = re.findall(r'X\((\d), (\d), (\d), ((?:0x[0-9A-F]{2}(?:, )?){9})\)', tables)
    parsed = [(int(d), int(v), [int(k, 16) for k in keys.split(', ')]) for _, d, v, keys in records]
    if parsed != DEFAULT_RECORDS:
        problems.append('default records differ: %s' % parsed)
    names = {}
    for code, english in re.findall(r'X\((0x[0-9A-F]{2}), "((?:[^"\\]|\\.)*)"', tables):
        names[int(code, 16)] = english.encode('latin-1').decode('unicode_escape')
    if names != BINDABLE:
        problems.append('bindable names differ: %s' % sorted(set(names.items()) ^ set(BINDABLE.items())))
    count = re.search(r'#define PAGE25_BINDABLE_KEY_COUNT\s+(\d+)', tables)
    if not count or int(count.group(1)) != BINDABLE_COUNT:
        problems.append('PAGE25_BINDABLE_KEY_COUNT differs')
    page = (engine / PAGE_C).read_text(encoding='latin-1')
    frames = re.search(r'#define P25_SLIDE_FRAMES (\d+)', page)
    if not frames or int(frames.group(1)) != SLIDE_FRAMES:
        problems.append('P25_SLIDE_FRAMES differs')
    for name, value in (('ESCAPE', ESCAPE), ('RETURN', RETURN), ('F1', F1), ('F2', F2), ('F3', F3),
                        ('LEFT', LEFT), ('RIGHT', RIGHT)):
        match = re.search(r'#define P25_DIK_%s\s+0x([0-9A-F]{2})u' % name, page)
        if not match or int(match.group(1), 16) != value:
            problems.append('P25_DIK_%s differs' % name)
    sfx = dict(re.findall(r'#define P25_SFX_(\w+)\s+(SFX_\w+)', page))
    wanted = {'REFUSE': 'SFX_GEN_FROG_CROAK', 'CURSOR': 'SFX_GEN_FROG_HOP', 'PAGE': 'SFX_GEN_FROG_SUPER_HOP',
              'ACCEPT': 'SFX_GEN_FROG_HIT_GROUND', 'BACK': 'SFX_GEN_FROG_SLURP', 'ENTER': 'SFX_GEN_CLOCK_TICK'}
    if sfx != wanted:
        problems.append('page sounds differ: %s' % sfx)
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
    for _, sound, froglord, _ in EVENTS:
        if sound and generic[SOUND_IDS[sound]] != froglord:
            problems.append('%s is %s in FrogLord, not %s' % (sound, generic[SOUND_IDS[sound]], froglord))
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--froggy-reference', type=Path, default=DEFAULT_FROGGY,
                        help='froggy engine folder (default: ../froggy/engine)')
    parser.add_argument('--check', action='store_true', help='compare with the committed file instead of writing')
    args = parser.parse_args()
    problems = check_sound_names()
    if (args.froggy_reference / TABLES_H).is_file() and (args.froggy_reference / PAGE_C).is_file():
        problems += check_froggy(args.froggy_reference)
        if not problems:
            print('froggy cross-check passed against %s' % args.froggy_reference)
    else:
        print('froggy tables not found at %s; cross-checks skipped' % args.froggy_reference)
    for problem in problems:
        print('cross-check: ' + problem)
    if problems:
        sys.exit(1)
    text = stack.dump(document()) + '\n'
    if args.check:
        old = CONTROLS_JSON.read_text(encoding='utf-8') if CONTROLS_JSON.exists() else ''
        if old != text:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                       str(CONTROLS_JSON), 'generated', n=0))
        print('Committed facts differ from the generator' if old != text else 'Committed facts match the generator')
        sys.exit(1 if old != text else 0)
    CONTROLS_JSON.write_text(text, encoding='utf-8')
    print('Wrote %s' % CONTROLS_JSON.relative_to(ROOT))


if __name__ == '__main__':
    main()
