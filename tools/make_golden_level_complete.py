#!/usr/bin/env python3
"""Independent retail level-complete page facts and scripted page traces.

Transcribes LevelCompleteStartup and LevelCompleteUpdate (tempopt.c), the
count-down defines (tempopt.h), HUDGetDigits and the checkpoint animlists
(HUD.C), the gold-frog animlist (tempopt.c), the checkpoint-seconds rounding
(FROG.C) and the overlay polygon (gamesys.C), then replays the page's 30 Hz
update over scripted fire/back ticks at the PC's 640x480 display.

The CD music comes from the retail executable, not the vendored PSX source
(FROGGER.EXE: LevelCompleteStartup 0x00444dc0, PlayZoneComplete 0x0043e580,
GameEnd 0x00430560, PauseCD 0x00430110): next level plays sound 8 and stops
the level track; zone complete plays no sound and starts disc track
Game_map_theme + 22 once in its place. With FROGGER_DATA_DIR (or --data-dir)
set, those facts are compared with the bytes of FROGGER.EXE through its PE
section table. See tests/golden/specs/frontend.md#level-complete.
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
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_golden_frontend as frontend
import make_golden_game_over as game_over
import make_golden_stack as stack

ROOT = frontend.ROOT
LEVEL_COMPLETE_JSON = frontend.GOLDEN / 'synthetic' / 'frontend_level_complete.json'
SOUND_CFG = ROOT / 'archive' / 'third_party' / 'froglord_cfg' / 'sounds' / '1997-11-19-pc-retail.cfg'

DISPLAY_W, DISPLAY_H = 640, 480
CENTRE_X, CENTRE_Y = DISPLAY_W >> 1, DISPLAY_H >> 1
MASK = 0xFFFFFFFF

UNIT_TICKS = 31
START_UNITS = 20
LAST_UNITS = 17
FIRE_UNITS = 19
BLINK_BIT = 16

CHECKPOINTS = 5
CEL_COUNT = 7
CHECKPOINT_CEL_TICKS = 2
GOLD_CEL_TICKS = 1
TICKS_PER_SECOND = 30
SECONDS_LIMIT_TICKS = 2971
SECONDS_LIMIT = 99
HUD_DIGITS = 10

OVERLAY_RGB = 0x60
OVERLAY_ALPHA = 0.5

SOUNDS = {'SFX_GEN_FROG_CROAK': (3, 'GEN_FROG_CROAK'), 'SFX_MUSIC_LEVEL_COMPLETE': (8, 'MUSIC_LEVELCOMP')}
SOUND_CROAK = SOUNDS['SFX_GEN_FROG_CROAK'][0]
SOUND_LEVEL_COMPLETE = SOUNDS['SFX_MUSIC_LEVEL_COMPLETE'][0]

CHECKPOINT_X, CHECKPOINT_Y, CHECKPOINT_PITCH = -105, -70, 20
TIME_TENS_X, TIME_UNITS_X, TIME_SEC_X = -84, -68, -52
TOTAL_TEXT = (-16, -60)
TOTAL_DIGIT_X, TOTAL_Y, TOTAL_SEC_X = [10, 26, 42], -40, 58
TOTAL_DIGIT_SLOTS = [7, 8, 9]
SCORE_TEXT = (-22, -15)
SCORE_DIGIT_X, SCORE_NUDGE, SCORE_Y = [-16, 0, 16, 32, 48, 64], 6, 5
SCORE_DIGIT_SLOTS = [4, 5, 6, 7, 8, 9]
GOLD_AT = (-105, 30)
NEXT_BOTTOM = {'next': 90, 'level_name': 70, 'press_fire': 50, 'select4': 30}
ZONE_BOTTOM = {'zone_complete': 50, 'press_fire': 32}

THEMES = ['GEN', 'CAV', 'DES', 'FOR', 'JUN', 'ORG', 'ARN', 'SWP', 'SKY', 'SUB', 'VOL', 'TIT', 'HUD', 'FRG']
ZONE_THEMES = THEMES[1:11]
ZONE_TRACK_BASE = 22

IMAGE_BASE = game_over.IMAGE_BASE
TEXT_VMA = game_over.TEXT_VMA
PLAY_CD, STOP_CD, PAUSE_CD, RESUME_CD = 0x004300a0, 0x004300e0, 0x00430110, 0x00430140
CD_STOP = 0x00446580
GAME_END = 0x00430560
PLAY_ZONE_COMPLETE = 0x0043e580
PLAY_SOUND = 0x0044c290
SET_VOLUME = 0x0044cd40
CD_VOLUME_CHANNEL = 3
VOLUME_STAGES = 8
GAME_MAP_THEME = 0x00495118
SOUND_VOLUME = 0x004853dc
CD_PAUSED = 0x00478548
CD_TRACK = 0x00478544
CD_PLAYING = 0x00478540
CD_PRESENT = 0x00496f80
ZONE_BRANCH = (0x004454e6, 0x00445591)

VARIANTS = ['NEXT_LEVEL', 'ZONE_COMPLETE', 'STATISTICS']
WIDTHS = {'next': 64, 'level_name': 200, 'press_fire': 128, 'select4': 160, 'zone_complete': 192}


def hud_digits(value):
    """HUDGetDigits: ten decimal digits, Hud_digits[9] the units."""
    digits = [0] * HUD_DIGITS
    value &= MASK
    for slot in range(HUD_DIGITS - 1, -1, -1):
        digits[slot] = value % 10
        value //= 10
    return digits


def last_digits(value, count):
    return ''.join(str(d) for d in hud_digits(value)[HUD_DIGITS - count:])


def checkpoint_seconds(ticks):
    """Frog_time_data from a checkpoint's Game_map_timer_decimalised (FROG.C:2833-2842)."""
    value = ticks
    while value != 0 and value != (value // TICKS_PER_SECOND) * TICKS_PER_SECOND:
        value += 1
    if value >= SECONDS_LIMIT_TICKS:
        return SECONDS_LIMIT
    return value // TICKS_PER_SECOND


def animlist_cel(frame, speed):
    """MR_SPRT_SETSPEED speed over CEL_COUNT images with LOOPBACK."""
    return (frame // speed) % CEL_COUNT


def checkpoint_image(checkpoint, frame):
    return 'babyfrog%d_%d' % (checkpoint + 1, animlist_cel(frame, CHECKPOINT_CEL_TICKS))


def gold_image(frame):
    return 'babyfroggold_%d' % animlist_cel(frame, GOLD_CEL_TICKS)


def zone_track(theme):
    """Disc track theme + 22 for the ten zone themes; the port plays none for any other theme."""
    return theme + ZONE_TRACK_BASE if THEMES[theme] in ZONE_THEMES else -1


def le32(value):
    return game_over.le32(value)


def call(address, target):
    return game_over.call(address, target)


def absolute(address):
    return le32(address)


def exe_pins():
    """Retail instruction bytes the page's music rests on: address, bytes and meaning."""
    pins = [
        (0x004454cc, '6a00' '6a00' '6a00' '6a%02x' % SOUND_LEVEL_COMPLETE + call(0x004454d4, PLAY_SOUND) + '83c410'
         + call(0x004454dc, PAUSE_CD) + 'e9' + le32(0x00445620 - 0x004454e6),
         'LevelCompleteStartup, next level: MRSNDPlaySound(SFX_MUSIC_LEVEL_COMPLETE) at 0x0044c290, then PauseCD '
         'at 0x00430110, then past the zone-complete block'),
        (0x00445561, 'a0' + absolute(SOUND_VOLUME) + '84c0' '7422' '33c0' 'a0' + absolute(SOUND_VOLUME) + '8bc8'
         'c1e007' '2bc1' '99' '83e2%02x' '03c2' 'c1f8%02x' '50' '6a%02x' % (
             VOLUME_STAGES - 1, VOLUME_STAGES.bit_length() - 1, CD_VOLUME_CHANNEL)
         + call(0x00445584, SET_VOLUME) + '83c408' + call(0x0044558c, PLAY_ZONE_COMPLETE),
         'LevelCompleteStartup, zone complete: with Sound_volume set, MRSNDSetVolumeLevel(MRSND_CD_VOLUME, '
         '127 * Sound_volume / 8), then PlayZoneComplete at 0x0043e580, with no StopCD first'),
        (PLAY_ZONE_COMPLETE, '6a00' 'a1' + absolute(GAME_MAP_THEME) + '83c0%02x' '50' % ZONE_TRACK_BASE
         + call(0x0043e58b, PLAY_CD) + '83c408' 'c3',
         'PlayZoneComplete: PlayCD(Game_map_theme + 22, 0): the zone tune once'),
        (0x00445902, call(0x00445902, GAME_END), 'LevelCompleteShutdown: GameEnd at 0x00430560'),
        (GAME_END, '5657' + call(0x00430562, STOP_CD), 'GameEnd begins with StopCD at 0x004300e0'),
        (STOP_CD, 'a0' + absolute(CD_PRESENT) + '84c0' '7422' 'a1' + absolute(CD_PLAYING) + '85c0' '7419'
         + call(0x004300f2, CD_STOP),
         'StopCD: with a CD and a track playing, the MCI stop at 0x00446580'),
        (PAUSE_CD, 'a0' + absolute(CD_PRESENT) + '84c0' '7418' 'a1' + absolute(CD_PAUSED) + '85c0' '750f'
         'c705' + absolute(CD_PAUSED) + le32(1) + 'e9' + le32(CD_STOP - 0x00430131),
         'PauseCD: unless already paused, set the paused flag and jump to the same MCI stop; the track is kept'),
    ]
    return [{'address': '0x%08x' % address, 'bytes_hex': data, 'meaning': meaning}
            for address, data, meaning in pins]


def exe_absent_calls():
    """Instruction ranges that call no routine of target: start, end, target and meaning."""
    return [{'start': '0x%08x' % ZONE_BRANCH[0], 'end': '0x%08x' % ZONE_BRANCH[1], 'target': '0x%08x' % PLAY_SOUND,
             'meaning': 'the zone-complete block plays no sound: no MRSNDPlaySound, so no sound 8'}]


def check_exe(exe_path, pins, absent=()):
    """Compare pinned bytes with FROGGER.EXE and confirm the absent calls; returns problems."""
    data = exe_path.read_bytes()
    try:
        image_base, sections = game_over.pe_sections(data)
    except ValueError as error:
        return ['%s: %s' % (exe_path, error)]
    problems = []
    if image_base != IMAGE_BASE:
        problems.append('image base is 0x%08x, not 0x%08x' % (image_base, IMAGE_BASE))
    text = [section for section in sections if section[0] == '.text']
    if not text or image_base + text[0][1] != TEXT_VMA:
        return problems + ['.text does not start at 0x%08x' % TEXT_VMA]
    _name, vaddr, vsize, raw_size, raw_offset = text[0]
    start, end = image_base + vaddr, image_base + vaddr + min(vsize, raw_size)

    def read(address, length):
        if not (start <= address and address + length <= end):
            return None
        offset = raw_offset + address - start
        return data[offset:offset + length]

    for pin in pins:
        expected = bytes.fromhex(pin['bytes_hex'])
        actual = read(int(pin['address'], 16), len(expected))
        if actual is None:
            problems.append('%s lies outside .text' % pin['address'])
        elif actual != expected:
            problems.append('%s is %s, pinned %s: %s' % (pin['address'], actual.hex(), pin['bytes_hex'], pin['meaning']))
    for rule in absent:
        first, last, target = (int(rule[key], 16) for key in ('start', 'end', 'target'))
        block = read(first, last - first)
        if block is None:
            problems.append('%s-%s lies outside .text' % (rule['start'], rule['end']))
            continue
        for index in range(len(block) - 4):
            if block[index] == 0xE8 and first + index + 5 + struct.unpack_from('<i', block, index + 1)[0] == target:
                problems.append('0x%08x calls %s: %s' % (first + index, rule['target'], rule['meaning']))
    return problems


def centred_x(width):
    return CENTRE_X - (width >> 1)


class Page:
    """LevelCompleteStartup's count-down and LevelCompleteUpdate's input handling."""

    def __init__(self, variant, next_level, checkpoint_ticks, level_score, show_gold_frog):
        self.variant = variant
        self.next_level = next_level
        self.seconds = [checkpoint_seconds(t) for t in checkpoint_ticks]
        self.total = sum(self.seconds)
        self.score = level_score
        self.gold = show_gold_frog
        self.units, self.ticks = START_UNITS, UNIT_TICKS
        self.frame = 0
        self.press_fire_visible = False
        self.exit = None
        self.sounds = []

    def startup_sounds(self):
        return [SOUND_LEVEL_COMPLETE] if self.variant == 'NEXT_LEVEL' else []

    def stops_music(self):
        """PauseCD after sound 8 (0x004454dc): next level only."""
        return self.variant == 'NEXT_LEVEL'

    def startup_track(self, theme):
        """PlayZoneComplete's PlayCD(Game_map_theme + 22, 0): zone complete only."""
        return zone_track(theme) if self.variant == 'ZONE_COMPLETE' else -1

    def shows_prompt(self):
        return self.variant != 'STATISTICS'

    def accepts_fire(self):
        return self.shows_prompt() and self.units < FIRE_UNITS

    def tick(self, fire, back):
        if self.exit is not None:
            return
        self.frame += 1
        self.sounds = []
        self.ticks = (self.ticks - 1) & MASK
        if self.ticks == 0 and self.units > LAST_UNITS:
            self.units -= 1
            self.ticks = UNIT_TICKS
        prompt = self.shows_prompt()
        if prompt and self.units < FIRE_UNITS:
            if fire:
                self.units, self.ticks = 0, 0
                self.sounds.append(SOUND_CROAK)
            self.press_fire_visible = (self.frame & BLINK_BIT) == 0
        if prompt and back:
            self.exit = 'BACK'
        elif prompt and self.units == 0 and self.ticks == 0:
            self.exit = 'NEXT_LEVEL' if self.variant == 'NEXT_LEVEL' else 'ZONE_COMPLETE'

    def row(self):
        return [self.frame, self.units, self.ticks, self.accepts_fire(), self.press_fire_visible,
                list(self.sounds), self.exit]


def sprites(page, widths):
    out = []

    def put(image, x, y):
        out.append({'image': image, 'x': x, 'y': y})

    for j in range(CHECKPOINTS):
        y = CENTRE_Y + CHECKPOINT_Y + j * CHECKPOINT_PITCH
        digits = hud_digits(page.seconds[j] if j < len(page.seconds) else 0)
        put(checkpoint_image(j, page.frame), CENTRE_X + CHECKPOINT_X, y)
        put('med_%d' % digits[8], CENTRE_X + TIME_TENS_X, y)
        put('med_%d' % digits[9], CENTRE_X + TIME_UNITS_X, y)
        put('opt_sec', CENTRE_X + TIME_SEC_X, y)
    put('total_time', CENTRE_X + TOTAL_TEXT[0], CENTRE_Y + TOTAL_TEXT[1])
    digits = hud_digits(page.total)
    for x, slot in zip(TOTAL_DIGIT_X, TOTAL_DIGIT_SLOTS):
        put('med_%d' % digits[slot], CENTRE_X + x, CENTRE_Y + TOTAL_Y)
    put('opt_sec', CENTRE_X + TOTAL_SEC_X, CENTRE_Y + TOTAL_Y)
    put('total_score', CENTRE_X + SCORE_TEXT[0], CENTRE_Y + SCORE_TEXT[1])
    digits = hud_digits(page.score)
    for x, slot in zip(SCORE_DIGIT_X, SCORE_DIGIT_SLOTS):
        put('med_%d' % digits[slot], CENTRE_X + x + SCORE_NUDGE, CENTRE_Y + SCORE_Y)
    if page.gold:
        put(gold_image(page.frame), CENTRE_X + GOLD_AT[0], CENTRE_Y + GOLD_AT[1])
    if page.variant == 'NEXT_LEVEL':
        bottom = NEXT_BOTTOM
    elif page.variant == 'ZONE_COMPLETE':
        bottom = ZONE_BOTTOM
    else:
        bottom = {}
    for image, rise in sorted(bottom.items(), key=lambda item: -item[1]):
        if image == 'press_fire' and not page.press_fire_visible:
            continue
        put(image, centred_x(widths.get(image, 0)), DISPLAY_H - rise)
    return out


SCENES = [
    ('next_level_idle', 'NEXT_LEVEL', 25, [30, 31, 60, 2971, 0], 1850, True, {}, 200, [0, 70], 10000, 'ORG'),
    ('fire_at_61_then_62', 'NEXT_LEVEL', 25, [30, 31, 60, 2971, 0], 1850, True,
     {61: ['fire'], 62: ['fire']}, 200, [0, 62], None, 'ORG'),
    ('back_at_1', 'NEXT_LEVEL', 25, [0, 0, 0, 0, 0], 0, False, {1: ['back']}, 200, [0, 1], None, 'SUB'),
    ('fire_and_back_at_70', 'NEXT_LEVEL', 3, [450, 900, 1350, 1800, 2250], 123456, True,
     {70: ['fire', 'back']}, 200, [0, 70], None, 'CAV'),
    ('zone_fire_at_100', 'ZONE_COMPLETE', -1, [29, 59, 89, 2940, 2941], 9876543, True,
     {100: ['fire']}, 200, [0, 100], None, 'SWP'),
    ('statistics_ignores_keys', 'STATISTICS', -1, [300, 600, 900, 1200, 1500], 42, False,
     {70: ['fire'], 80: ['back']}, 200, [0, 70], None, 'VOL'),
    ('next_level_idle_wraps', 'NEXT_LEVEL', 25, [30, 31, 60, 2971, 0], 1850, True, {}, 130, [125], None, 'ORG'),
]


def run(name, variant, next_level, checkpoint_ticks, score, gold, inputs, ticks, sprite_frames, no_exit_after,
        theme_name):
    page = Page(variant, next_level, checkpoint_ticks, score, gold)
    theme = THEMES.index(theme_name)
    scene = {'name': name, 'variant': variant, 'next_level': next_level, 'checkpoint_ticks': checkpoint_ticks,
             'level_score': score, 'show_gold_frog': gold, 'theme': theme, 'checkpoint_seconds': page.seconds,
             'total_seconds': page.total, 'startup_sounds': page.startup_sounds(),
             'stops_music': page.stops_music(), 'startup_track': page.startup_track(theme),
             'shows_prompt': page.shows_prompt(),
             'inputs': {str(k): v for k, v in sorted(inputs.items())}, 'ticks': ticks}
    if no_exit_after is not None:
        probe = Page(variant, next_level, checkpoint_ticks, score, gold)
        for _ in range(no_exit_after):
            probe.tick(False, False)
            if probe.exit is not None:
                raise SystemExit('%s exits at %d' % (name, probe.frame))
        scene['no_exit_after'] = no_exit_after
    trace = []
    for tick in range(1, ticks + 1):
        keys = inputs.get(tick, [])
        page.tick('fire' in keys, 'back' in keys)
        trace.append(page.row())
        if page.exit is not None:
            break
    scene['trace'] = trace
    shots = []
    for frame in sprite_frames:
        shot = Page(variant, next_level, checkpoint_ticks, score, gold)
        for tick in range(1, frame + 1):
            keys = inputs.get(tick, [])
            shot.tick('fire' in keys, 'back' in keys)
        shots.append({'frame': frame, 'widths': WIDTHS, 'sprites': sprites(shot, WIDTHS)})
    scene['sprites_at'] = shots
    return scene


def document():
    return {
        'source': 'tempopt.c:5792-6067 LevelCompleteStartup/Update, HUD.C:2522 HUDGetDigits, FROG.C:2833-2842; '
                  'FROGGER.EXE 0x00444dc0 and 0x0043e580 for the music',
        'constants': {'start_units': START_UNITS, 'unit_ticks': UNIT_TICKS, 'last_units': LAST_UNITS,
                      'fire_units': FIRE_UNITS, 'blink_bit': BLINK_BIT, 'sound_level_complete': SOUND_LEVEL_COMPLETE,
                      'sound_croak': SOUND_CROAK, 'overlay_rgb': OVERLAY_RGB, 'overlay_alpha': OVERLAY_ALPHA,
                      'checkpoint_cel_ticks': CHECKPOINT_CEL_TICKS, 'gold_cel_ticks': GOLD_CEL_TICKS,
                      'cels': CEL_COUNT, 'zone_track_base': ZONE_TRACK_BASE},
        'zone_tracks': [{'theme': theme, 'name': name, 'track': zone_track(theme)} for theme, name in enumerate(THEMES)],
        'seconds': [{'ticks': t, 'seconds': checkpoint_seconds(t)}
                    for t in (0, 1, 29, 30, 31, 60, 61, 2940, 2941, 2970, 2971, 5000)],
        'centring': [{'width': w, 'x': centred_x(w)} for w in (0, 1, 2, 63, 64, 65, 127, 128, 255, 256, 640)],
        'digits': [{'value': v, 'count': c, 'text': last_digits(v, c)}
                   for v, c in ((1234, 3, ), (5, 2), (1850, 6), (0, 2), (99, 2), (495, 3), (1234567, 6), (7, 6))],
        'frames': [{'frame': f, 'checkpoint': c, 'checkpoint_image': checkpoint_image(c, f), 'gold_image': gold_image(f)}
                   for f, c in ((0, 0), (1, 1), (2, 2), (3, 3), (6, 4), (7, 0), (13, 1), (14, 2), (70, 4))],
        'scenes': [run(*scene) for scene in SCENES],
        'exe': {'file': 'FROGGER.EXE', 'image_base': '0x%08x' % IMAGE_BASE, 'text_vma': '0x%08x' % TEXT_VMA},
        'exe_pins': exe_pins(),
        'exe_absent_calls': exe_absent_calls(),
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


def at(axis, offset):
    """The C's centred coordinate expression, e.g. (Game_display_width>>1)-105."""
    return '(Game_display_%s>>1)%s' % (axis, '%+d' % offset if offset else '')


def startup_snippets():
    w = lambda o: at('width', o)
    h = lambda o: at('height', o)
    s = ['Options_count_down_ticks=NUM_GAME_OVER_TICKS;Options_count_down_units=%d;' % START_UNITS,
         'y=%s;for(j=0;j<GEN_MAX_CHECKPOINTS;j++){UpdateSpriteDisplay(Level_complete.Level_complete_checkpoints[j],'
         'Hud_checkpoint_animlists[j],%s,y);y+=%d;}' % (h(CHECKPOINT_Y), w(CHECKPOINT_X), CHECKPOINT_PITCH),
         'HUDGetDigits(Frog_time_data[j],&digit_a,&digit_b,&digit_c);total_time+=Frog_time_data[j];'
         'UpdateSpriteDisplay(*sprite_pptr,Hud_score_images[Hud_digits[8]],%s,y);'
         'UpdateSpriteDisplay(*++sprite_pptr,Hud_score_images[Hud_digits[9]],%s,y);'
         'UpdateSpriteDisplay(*++sprite_pptr,Options_text_textures[OPTION_TEXT_SEC][Game_language],%s,y);y+=%d;'
         % (w(TIME_TENS_X), w(TIME_UNITS_X), w(TIME_SEC_X), CHECKPOINT_PITCH),
         'HUDGetDigits(total_time,&digit_a,&digit_b,&digit_c);UpdateSpriteDisplay(Level_complete.'
         'Level_complete_total_time_text,Options_text_textures[OPTION_TEXT_TOTAL_TIME][Game_language],%s,%s);'
         % (w(TOTAL_TEXT[0]), h(TOTAL_TEXT[1]))]
    for index, (x, slot) in enumerate(zip(TOTAL_DIGIT_X, TOTAL_DIGIT_SLOTS)):
        s.append('UpdateSpriteDisplay(Level_complete.Level_complete_total_time[%d],Hud_score_images[Hud_digits[%d]],'
                 '%s,%s);' % (index, slot, w(x), h(TOTAL_Y)))
    s.append('UpdateSpriteDisplay(Level_complete.Level_complete_total_time[3],Options_text_textures[OPTION_TEXT_SEC]'
             '[Game_language],%s,%s);' % (w(TOTAL_SEC_X), h(TOTAL_Y)))
    s.append('value=Frog_score_data[Game_map][0].he_score;HUDGetDigits(value,&digit_a,&digit_b,&digit_c);'
             'UpdateSpriteDisplay(Level_complete.Level_complete_total_score_text,Options_text_textures'
             '[OPTION_TEXT_TOTAL_SCORE][Game_language],%s,%s);' % (w(SCORE_TEXT[0]), h(SCORE_TEXT[1])))
    for index, (x, slot) in enumerate(zip(SCORE_DIGIT_X, SCORE_DIGIT_SLOTS)):
        s.append('UpdateSpriteDisplay(Level_complete.Level_complete_total_score[%d],Hud_score_images[Hud_digits[%d]],'
                 '%s%+d,%s);' % (index, slot, w(x) if x else w(0) + '+0', SCORE_NUDGE, h(SCORE_Y)))
    s.append('UpdateSpriteDisplay(Level_complete.Level_complete_golden_frog,&Animlist_level_complete_golden_frog,'
             '%s,%s);' % (w(GOLD_AT[0]), h(GOLD_AT[1])))
    centred = '(Game_display_width>>1)-(texture->te_w>>1),Game_display_height-%d);'
    s.append('texture=Options_text_textures[OPTION_TEXT_NEXT][Game_language];UpdateSpriteDisplay(Level_complete.'
             'Level_complete_next_level_des,texture,' + centred % NEXT_BOTTOM['next'])
    s.append('UpdateSpriteDisplay(Level_complete.Level_complete_next_level_text,arcade_next_level_ptr->'
             'li_level_name_texture_in_game,(Game_display_width>>1)-(arcade_next_level_ptr->'
             'li_level_name_texture_in_game->te_w>>1),Game_display_height-%d);' % NEXT_BOTTOM['level_name'])
    s.append('texture=Options_text_textures[OPTION_TEXT_SELECT4][Game_language];UpdateSpriteDisplay(Level_complete.'
             'Level_complete_press_tri,texture,' + centred % NEXT_BOTTOM['select4'])
    s.append('texture=Options_text_textures[OPTION_TEXT_PRESS_FIRE][Game_language];UpdateSpriteDisplay('
             'Level_complete.Level_complete_press_fire,texture,' + centred % NEXT_BOTTOM['press_fire'] +
             'MRSNDPlaySound(SFX_MUSIC_LEVEL_COMPLETE,NULL,0,0);XAControl(XACOM_PAUSE,0);')
    s.append('#ifdefPSXif(Sound_volume)MRSNDSetVolumeLevel(MRSND_CD_VOLUME,(127*Sound_volume)/OPTIONS_SOUND_STAGES);'
             'PlayZoneComplete();#endif'
             'texture=Options_text_textures[OPTION_TEXT_ZONE_COMPLETE][Game_language];UpdateSpriteDisplay('
             'Level_complete.Level_complete_next_level_des,texture,' + centred % ZONE_BOTTOM['zone_complete'] +
             'texture=Options_text_textures[OPTION_TEXT_PRESS_FIRE][Game_language];UpdateSpriteDisplay('
             'Level_complete.Level_complete_press_fire,texture,' + centred % ZONE_BOTTOM['press_fire'])
    s.append('InitTransparentPolyBackground(0,0,Game_display_width,Game_display_height);'
             'Level_complete.Level_complete_press_fire->sp_core.sc_flags|=MR_SPF_NO_DISPLAY;')
    return s


def update_snippets():
    return [
        'Options_count_down_ticks--;if(!Options_count_down_ticks){if(Options_count_down_units>%d)'
        '{Options_count_down_units--;Options_count_down_ticks=NUM_GAME_OVER_TICKS;}}'
        'if(Options_count_down_units<%d){if(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],FR_GO))'
        '{Options_count_down_units=0;Options_count_down_ticks=0;MRSNDPlaySound(SFX_GEN_FROG_CROAK,NULL,0,0);}'
        'if(MRFrame_number&%d)Level_complete.Level_complete_press_fire->sp_core.sc_flags|=MR_SPF_NO_DISPLAY;'
        'elseLevel_complete.Level_complete_press_fire->sp_core.sc_flags&=~MR_SPF_NO_DISPLAY;}'
        'if(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],FRR_TRIANGLE)){Game_viewporth->vp_flags&=~MR_VP_NO_DISPLAY;'
        'Option_page_request=OPTIONS_PAGE_LEVEL_SELECT;' % (LAST_UNITS, FIRE_UNITS, BLINK_BIT),
        'elseif(!(Options_count_down_units||Options_count_down_ticks)){if(Sel_mode==SEL_MODE_ARCADE)'
        '{if(!Level_complete.Level_complete_next_level){Option_page_request=OPTIONS_PAGE_LEVEL_SELECT;}'
        'else{Option_page_request=OPTIONS_PAGE_GAME;',
        'MR_ULONGOptions_count_down_ticks;MR_ULONGOptions_count_down_units;',
    ]


def animlist(text, name, speed, prefix):
    images = ''.join('MR_SPRT_SETIMAGE,(MR_ULONG)&im_%s_%d,' % (prefix, i) for i in range(CEL_COUNT))
    return ('MR_ULONG%s[]={MR_SPRT_SETSPEED,%d,MR_SPRT_SETCOUNT,0,%sMR_SPRT_LOOPBACK};' % (name, speed, images)) in text


def check_c(c_root):
    """Compare the transcriptions above with the frozen C; returns problems."""
    problems = []
    header = (c_root / 'tempopt.h').read_text(encoding='latin-1')
    for name, value in (('NUM_OPTION_TICKS', str(UNIT_TICKS)), ('NUM_GAME_OVER_TICKS', 'NUM_OPTION_TICKS')):
        if stack.define(header, name) != value:
            problems.append('tempopt.h %s is %s, transcribed %s' % (name, stack.define(header, name), value))
    if stack.define((c_root / 'ent_gen.h').read_text(encoding='latin-1'), 'GEN_MAX_CHECKPOINTS') != '(%d)' % CHECKPOINTS:
        problems.append('ent_gen.h GEN_MAX_CHECKPOINTS differs')
    tempopt = strip_c((c_root / 'tempopt.c').read_text(encoding='latin-1'))
    for snippet in startup_snippets() + update_snippets():
        if snippet not in tempopt:
            problems.append('tempopt.c no longer contains: %s' % snippet[:100])
    if not animlist(tempopt, 'Animlist_level_complete_golden_frog', GOLD_CEL_TICKS, 'babyfroggold'):
        problems.append('tempopt.c gold-frog animlist differs')
    hud = strip_c((c_root / 'HUD.C').read_text(encoding='latin-1'))
    if ('digit_ptr=&Hud_digits[9];for(loop_counter=0;loop_counter<10;loop_counter++){remainder=value%10;'
            '*digit_ptr=(MR_UBYTE)remainder;value=value/10;digit_ptr--;}') not in hud:
        problems.append('HUD.C HUDGetDigits differs')
    for index in range(CHECKPOINTS):
        if not animlist(hud, 'Animlist_hud_checkpoint_%d' % (index + 1), CHECKPOINT_CEL_TICKS,
                        'babyfrog%d' % (index + 1)):
            problems.append('HUD.C Animlist_hud_checkpoint_%d differs' % (index + 1))
    order = ','.join('Animlist_hud_checkpoint_%d' % (i + 1) for i in range(CHECKPOINTS))
    if 'MR_ULONG*Hud_checkpoint_animlists[]={%s,};' % order not in hud:
        problems.append('HUD.C Hud_checkpoint_animlists order differs')
    frog = strip_c((c_root / 'FROG.C').read_text(encoding='latin-1'))
    if ('while(Game_map_timer_decimalised!=0&&(Game_map_timer_decimalised!=(Game_map_timer_decimalised/%d)*%d))'
            'Game_map_timer_decimalised++;if(Game_map_timer_decimalised>=%d){Frog_time_data[checkpoint_id]=%d;}'
            'else{Frog_time_data[checkpoint_id]=(Game_map_timer_decimalised)/%d;}'
            % (TICKS_PER_SECOND, TICKS_PER_SECOND, SECONDS_LIMIT_TICKS, SECONDS_LIMIT, TICKS_PER_SECOND)) not in frog:
        problems.append('FROG.C checkpoint seconds rounding differs')
    gamesys_h = strip_c((c_root / 'gamesys.H').read_text(encoding='latin-1'))
    if 'enum{%s,};' % ','.join('THEME_' + name for name in THEMES) not in gamesys_h:
        problems.append('gamesys.H theme enum differs from %s' % ', '.join(THEMES))
    gamesys = strip_c((c_root / 'gamesys.C').read_text(encoding='latin-1'))
    for snippet in ('setRGB0(&Game_prim_f[j],0x%x,0x%x,0x%x);setSemiTrans(&Game_prim_f[j],1);'
                    % (OVERLAY_RGB, OVERLAY_RGB, OVERLAY_RGB),
                    '#ifdefPSXGame_prim_ft[j].tpage=defTPage(0,0,2);#elseGame_prim_ft[j].tpage=0;#endif'):
        if snippet not in gamesys:
            problems.append('gamesys.C no longer contains: %s' % snippet[:100])
    sound = (c_root / 'sound.h').read_text(encoding='latin-1')
    body = re.search(r'In the GENERIC VAB\.\s*(.*?)\}', sound, flags=re.S)
    generic = re.findall(r'^\s*(SFX_\w+)\s*,', body.group(1), flags=re.M) if body else []
    for name, (value, _froglord) in SOUNDS.items():
        if name not in generic or generic.index(name) != value:
            problems.append('sound.h %s is not %d' % (name, value))
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
            exe_problems = check_exe(exe, exe_pins(), exe_absent_calls())
            problems += exe_problems
            if not exe_problems:
                print('Executable pins passed against %s (%d pins)' % (exe, len(exe_pins())))
    else:
        print('FROGGER_DATA_DIR not set; executable pins skipped')
    for problem in problems:
        print('cross-check: ' + problem)
    if problems:
        sys.exit(1)
    text = dump(document()) + '\n'
    if args.check:
        old = LEVEL_COMPLETE_JSON.read_text(encoding='utf-8') if LEVEL_COMPLETE_JSON.exists() else ''
        if old != text:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                       str(LEVEL_COMPLETE_JSON), 'generated', n=0))
        print('Committed facts differ from the generator' if old != text else 'Committed facts match the generator')
        sys.exit(1 if old != text else 0)
    LEVEL_COMPLETE_JSON.write_text(text, encoding='utf-8')
    print('Wrote %s' % LEVEL_COMPLETE_JSON.relative_to(ROOT))


if __name__ == '__main__':
    main()
