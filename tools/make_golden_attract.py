#!/usr/bin/env python3
"""Independent attract-cycle facts from the frozen C.

Transcribes MainOptionsUpdate's demo and high-score-view arms (tempopt.c), the
SCORE_TIME and fly-time defines (tempopt.h), HSUpdateFlying (HSView.c), the
Demo_time count-down (gamesys.C) and Demo_level_table (tempopt.c), then
replays the DEMO_FINISH search over three selectable sets and one attract pass
call by call. See tests/golden/specs/frontend.md#attract-cycle.
"""
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
import make_golden_stack as stack

ROOT = frontend.ROOT
ATTRACT_JSON = frontend.GOLDEN / 'synthetic' / 'frontend_attract.json'
DEMOS_TSV = frontend.GOLDEN / 'pc-retail-v3.0e' / 'exe_demos.tsv'

SCORE_TIME = 30 * 27
FLY_TIME = 10
FADE_UNITS = 30
DEMO_END_TICKS = 30
LOADING_BRIGHTEN = 16
MENU_SLIDE = 8
VIEW_INIT_OFFSET = 90
GAME_START_CALLS = 3
DEMO_FRAMES = 100
CYCLE_STEPS = 24
INTRO = -2

STATUS_DEMO_INIT, STATUS_DEMO_MAIN, STATUS_DEMO_FADE_OUT, STATUS_DEMO_FINISH = 0, 1, 2, 3
STATUS_VIEW_INIT, STATUS_VIEW_MAIN, STATUS_VIEW_FINISH = 4, 5, 6

DEMO_LEVEL_TABLE = [
    ('SUBURBIA1', 'SUBURBIA1'), ('DESERT1', 'DESERT1'), ('SKY3', 'SKY1'), ('CAVES1', 'CAVES1'),
    ('SWAMP5', 'SWAMP1'), ('FOREST1', 'FOREST1'), ('VOLCANO1', 'VOLCANO1'),
    None,
    ('ORIGINAL1', 'ORIGINAL1'), ('DESERT3', 'DESERT1'), ('SUBURBIA5', 'SUBURBIA1'), ('CAVES4', 'CAVES1'),
    ('SKY2', 'SKY1'), ('SWAMP1', 'SWAMP1'), ('ORIGINAL4', 'ORIGINAL1'), ('FOREST2', 'FOREST1'),
    None,
    ('VOLCANO3', 'VOLCANO1'), ('ORIGINAL2', 'ORIGINAL1'), ('SUBURBIA3', 'SUBURBIA1'), ('SKY4', 'SKY1'),
    ('SWAMP3', 'SWAMP1'), ('DESERT4', 'DESERT1'), ('VOLCANO2', 'VOLCANO1'), ('SWAMP2', 'SWAMP1'),
    ('DESERT2', 'DESERT1'),
    None,
    ('ORIGINAL3', 'ORIGINAL1'), ('SKY1', 'SKY1'), ('SUBURBIA4', 'SUBURBIA1'), ('SWAMP4', 'SWAMP1'),
    ('ORIGINAL5', 'ORIGINAL1'), ('DESERT5', 'DESERT1'), ('SUBURBIA2', 'SUBURBIA1'),
]
RESOURCE_NAMES = {'SUBURBIA': 'SUB', 'DESERT': 'DES', 'SKY': 'SKY', 'CAVES': 'CAV', 'SWAMP': 'SWP',
                  'FOREST': 'FOR', 'VOLCANO': 'VOL', 'ORIGINAL': 'ORG'}
CODE_THEMES = ['CAV', 'DES', 'FOR', 'JUN', 'ORG', 'ARN', 'SWP', 'SKY', 'SUB', 'VOL']


def table_rows():
    """Demo_level_table as [level, gate] pairs, -2 for the play-intro rows, without the -1 terminator."""
    return [[INTRO, INTRO] if row is None else [frontend.LEVEL[row[0]], frontend.LEVEL[row[1]]]
            for row in DEMO_LEVEL_TABLE]


def level_code(level):
    if level == INTRO:
        return 'INTRO'
    return CODE_THEMES[level // 6] + ('M' if level % 6 == 5 else str(level % 6 + 1))


def finish(rows, seen, selectable):
    """DEMO_FINISH (tempopt.c:1578-1614): the next row and what it requests."""
    while True:
        seen += 1
        if seen == len(rows):
            seen = 0
        level, gate = rows[seen]
        if level == INTRO or gate in selectable:
            break
    if seen == 0:
        return INTRO, 0
    if rows[seen][0] == INTRO:
        return INTRO, seen + 1
    return rows[seen][0], seen


def cycle(rows, selectable):
    steps, seen = [], 0
    for _ in range(CYCLE_STEPS):
        result, seen = finish(rows, seen, selectable)
        steps.append([level_code(result), seen, level_code(rows[seen][0])])
    return steps


def selectable_sets():
    arcade = frontend.read_stacks(frontend.LEVEL_SELECT_TSV)['arcade']
    firsts, worlds = [], set()
    for row in arcade:
        if row['world'] not in worlds:
            worlds.add(row['world'])
            firsts.append(row['level'])
    initial = [frontend.LEVEL[name] for name, flags in frontend.INITIAL_FLAGS
               if flags & frontend.SELECTABLE and frontend.LEVEL[name] not in frontend.RACE_LEVELS]
    return [('fresh_boot', initial), ('fresh_boot_and_sky1', initial + [frontend.LEVEL['SKY1']]),
            ('world_firsts', firsts), ('all_open', [r['level'] for r in arcade])]


class MainOptions:
    """MainOptionsUpdate's attract variables and one call of it, as the C keeps them."""

    def __init__(self, demo_frames):
        self.status = STATUS_VIEW_INIT
        self.loading_mode = 'INIT'
        self.game_start = 0
        self.score_time = 0
        self.flyon = FLY_TIME
        self.flyoff = 0
        self.sprite = FLY_TIME * MENU_SLIDE
        self.colour = 0
        self.units = 0
        self.grey = 0
        self.demo_time = 0
        self.demo_frames = demo_frames
        self.demo_loading = False

    def hs_update_flying(self):
        if self.flyon:
            self.flyon -= 1
        if self.flyoff:
            self.flyoff -= 1

    def call(self):
        status = self.status
        if status == STATUS_DEMO_INIT:
            if self.loading_mode == 'INIT':
                self.demo_loading = True
                self.flyoff, self.flyon = FLY_TIME, 0
                self.colour = 0
                self.loading_mode = 'LOADING'
            elif self.loading_mode == 'LOADING':
                was = self.flyoff
                self.flyoff -= 1
                if was:
                    self.sprite += MENU_SLIDE
                    self.colour += LOADING_BRIGHTEN
                if not self.flyoff:
                    self.loading_mode, self.game_start = 'GAME_START', 0
            elif self.loading_mode == 'GAME_START':
                self.game_start += 1
                if self.game_start == GAME_START_CALLS:
                    self.loading_mode = 'LEVEL_START'
            else:
                self.demo_time = self.demo_frames
                self.status = STATUS_DEMO_MAIN
                self.loading_mode = 'INIT'
                self.flyon, self.flyoff = FLY_TIME, 0
                self.demo_loading = False
        elif status == STATUS_DEMO_MAIN:
            if self.flyon:
                self.sprite -= MENU_SLIDE
                self.flyon -= 1
            if self.demo_time > 0:
                self.demo_time -= 1
            if self.demo_time == DEMO_END_TICKS:
                self.status = STATUS_DEMO_FADE_OUT
                self.units = FADE_UNITS
                self.flyoff, self.flyon = FLY_TIME, 0
                self.colour = 0
        elif status == STATUS_DEMO_FADE_OUT:
            if self.demo_time > 0:
                self.demo_time -= 1
            if self.flyoff:
                self.sprite += MENU_SLIDE
                self.colour += LOADING_BRIGHTEN
                self.flyoff -= 1
            self.units -= 1
            self.grey = min(0xff, ((FADE_UNITS - self.units) * 0xff) // FADE_UNITS)
            if not self.units:
                self.status = STATUS_DEMO_FINISH
        elif status == STATUS_DEMO_FINISH:
            self.status = STATUS_VIEW_INIT
        elif status == STATUS_VIEW_FINISH:
            self.status = STATUS_DEMO_INIT
        if status in (STATUS_VIEW_INIT, STATUS_VIEW_MAIN):
            if status == STATUS_VIEW_INIT:
                self.sprite = VIEW_INIT_OFFSET
                self.flyon = FLY_TIME
                self.score_time = SCORE_TIME
                self.status = STATUS_VIEW_MAIN
            self.hs_update_flying()
            if self.flyoff:
                self.sprite += MENU_SLIDE
            elif self.flyon:
                self.sprite -= MENU_SLIDE
            if not self.flyoff and not self.flyon:
                was = self.score_time
                self.score_time = (self.score_time - 1) & 0xFFFFFFFF
                if not was:
                    self.status = STATUS_VIEW_FINISH
        return status


def rle(values):
    runs = []
    for value in values:
        if runs and runs[-1][0] == value:
            runs[-1][1] += 1
        else:
            runs.append([value, 1])
    return runs


def port_slide(phase, fly_on, fly_off):
    """The port's menu offset below its rest rows (AttractTimer.menu_slide)."""
    if phase in ('LOADING', 'FADE_OUT') or (phase == 'DWELL' and fly_off):
        return (FLY_TIME - fly_off) * MENU_SLIDE
    if phase == 'FINISHED':
        return FLY_TIME * MENU_SLIDE
    return fly_on * MENU_SLIDE


def attract_pass():
    """One pass of the C, VIEW_INIT to DEMO_FINISH, with the calls grouped by the port's ticks."""
    c = MainOptions(DEMO_FRAMES)
    statuses = []
    rest = None

    def run():
        status = c.call()
        statuses.append(status)
        return status

    run()
    view_init = {'phase': 'DWELL', 'fly_on': c.flyon, 'score_time': c.score_time,
                 'menu_slide': port_slide('DWELL', c.flyon, c.flyoff), 'c_sprite_offset': c.sprite}
    samples, phases, call = [], [], 0
    while c.status == STATUS_VIEW_MAIN:
        run()
        call += 1
        exited = c.status != STATUS_VIEW_MAIN
        phase = 'LOADING' if exited else 'DWELL'
        phases.append(phase)
        score = 0 if exited else c.score_time
        if call <= 12 or call >= SCORE_TIME + FLY_TIME - 3:
            fly_on, fly_off = (0, FLY_TIME) if exited else (c.flyon, c.flyoff)
            samples.append([call, phase, fly_on, score, port_slide(phase, fly_on, fly_off), c.sprite])
        if exited:
            rest = c.sprite
    view_main_calls = call
    run()
    run()
    loading = []
    while c.loading_mode == 'LOADING':
        run()
        done = c.loading_mode != 'LOADING'
        fly_off = 0 if done else c.flyoff
        loading.append([fly_off, c.colour, done, port_slide('LOADING', 0, fly_off), c.sprite])
    while c.status == STATUS_DEMO_INIT:
        run()
    playing, playing_phases = [], []
    while c.status == STATUS_DEMO_MAIN:
        run()
        phase = 'PLAYING' if c.status == STATUS_DEMO_MAIN else 'FADE_OUT'
        playing_phases.append(phase)
        if len(playing) < 12:
            playing.append([c.demo_time, c.flyon, port_slide(phase, c.flyon, c.flyoff), c.sprite])
        switch_demo_time = c.demo_time
    fade = []
    while c.status == STATUS_DEMO_FADE_OUT:
        run()
        phase = 'FADE_OUT' if c.status == STATUS_DEMO_FADE_OUT else 'FINISHED'
        fade.append([phase, c.flyoff, c.colour, c.grey, port_slide(phase, 0, c.flyoff), c.sprite])
    run()
    return {
        'c_status_rle': rle(statuses),
        'c_rest_offset': rest,
        'start': {'phase': 'DWELL', 'score_time': SCORE_TIME, 'fly_on': FLY_TIME, 'fly_off': 0,
                  'menu_slide': port_slide('DWELL', FLY_TIME, 0), 'c_sprite_offset': VIEW_INIT_OFFSET},
        'view_init': view_init,
        'view_main_calls': view_main_calls,
        'view_main_phases': rle(phases),
        'view_main_samples': samples,
        'loading': loading,
        'demo_frames': DEMO_FRAMES,
        'playing_first': playing,
        'playing_phases': rle(playing_phases),
        'switch_demo_time': switch_demo_time,
        'fade': fade,
    }


def fire_gate():
    rows = []
    for fly_on in (0, 1, FLY_TIME):
        for fly_off in (0, 1, FLY_TIME):
            for loading in (False, True):
                for delayed in (False, True):
                    accepted = not fly_on and not fly_off and not loading and not delayed
                    rows.append([fly_on, fly_off, loading, delayed, accepted])
    return rows


def document(view_main_calls):
    rows = table_rows()
    cycles = {}
    for name, levels in selectable_sets():
        cycles[name] = {'selectable': sorted(levels), 'codes': [level_code(level) for level in levels],
                        'first': level_code(rows[0][0]), 'steps': cycle(rows, set(levels))}
    trace = attract_pass()
    return {
        'constants': {'score_time': SCORE_TIME, 'fly_time': FLY_TIME, 'fade_units': FADE_UNITS,
                      'demo_end_ticks': DEMO_END_TICKS, 'loading_brighten': LOADING_BRIGHTEN,
                      'menu_slide': MENU_SLIDE, 'view_main_calls': view_main_calls},
        'table': rows,
        'table_codes': [level_code(level) for level, _ in rows],
        'cycles': cycles,
        'dwell_trace': trace,
        'fire_gate': fire_gate(),
    }


def check_tsv(rows):
    problems = []
    lines = DEMOS_TSV.read_text(encoding='utf-8').splitlines()
    header = lines[0].lstrip('# ').split('\t')
    table, level, gate = header.index('table'), header.index('level'), header.index('unlock_level')
    got = [[int(f[level]), int(f[gate])] for f in (line.split('\t') for line in lines[1:] if line)
           if f[table] == 'high_poly']
    if got != rows:
        problems.append('exe_demos.tsv high_poly levels and gates differ from Demo_level_table')
    return problems


def strip_comments(text):
    return re.sub(r'//[^\n]*', '', re.sub(r'/\*.*?\*/', '', text, flags=re.S))


def check_c(c_root):
    """Compare the transcriptions above with the frozen C; returns problems."""
    problems = []
    header = (c_root / 'tempopt.h').read_text(encoding='latin-1')
    arm = re.search(r'#ifdef\s+PSX_RELEASE\s*\n\s*#define\s+SCORE_TIME\s+(\S+)', header)
    factors = re.fullmatch(r'(\d+)\*(\d+)', arm.group(1)) if arm else None
    if not factors or int(factors.group(1)) * int(factors.group(2)) != SCORE_TIME:
        problems.append('tempopt.h SCORE_TIME under PSX_RELEASE is not %d' % SCORE_TIME)
    if not re.search(r'^#define\s+PSX_RELEASE\b', (c_root / 'PC' / 'winsys.h').read_text(encoding='latin-1'), re.M):
        problems.append('PC/winsys.h no longer defines PSX_RELEASE')
    for name in ('OPTIONS_CAMERA_FLYOFF_TIME', 'OPTIONS_CAMERA_FLYON_TIME'):
        if stack.define(header, name) != str(FLY_TIME):
            problems.append('tempopt.h %s is %s, transcribed %d' % (name, stack.define(header, name), FLY_TIME))
    code = strip_comments((c_root / 'tempopt.c').read_text(encoding='latin-1'))
    flat = stack.squash(code)
    for snippet in ('if(Demo_time==%d)' % DEMO_END_TICKS,
                    'Options_count_down_units=%d;' % FADE_UNITS,
                    'i=MIN(0xff,((%d-Options_count_down_units)*0xff)/%d);' % (FADE_UNITS, FADE_UNITS),
                    'if(High_score_view_flyoff_counter--){Start_ptr->sp_pos.y+=%d;' % MENU_SLIDE,
                    'Sel_loading_sprite_ptr->sp_core.sc_base_colour.r+=%d;' % LOADING_BRIGHTEN,
                    'Start_ptr->sp_pos.y=Game_display_height-MAIN_MENU_Y_OFFSET+0+%d;' % VIEW_INIT_OFFSET,
                    'score_time=SCORE_TIME;',
                    '(!High_score_view_flyoff_counter)&&(!High_score_view_flyon_counter)&&'
                    '(!High_score_view_delayed_request)&&(!score_time--)',
                    '(!High_score_view_flyon_counter)&&(!High_score_view_flyoff_counter)&&(!Game_demo_loading)&&'
                    '(!High_score_view_delayed_request)&&(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],FR_GO))',
                    'do{Num_demo_levels_seen++;if(Demo_level_table[Num_demo_levels_seen][0]==-1)'
                    'Num_demo_levels_seen=0;if((Demo_level_table[Num_demo_levels_seen][0]==-2)||'
                    '((MR_USHORT)SelectGetLevelFlags(Demo_level_table[Num_demo_levels_seen][2])&SEL_LF_SELECTABLE))'
                    'valid_demo_level=TRUE;}while(valid_demo_level==FALSE);'
                    'if(Num_demo_levels_seen==0){Option_page_request=OPTIONS_PAGE_INTRO;',
                    'elseif(Demo_level_table[Num_demo_levels_seen][0]==-2){Option_page_request=OPTIONS_PAGE_INTRO;'
                    'Main_options_status=MAIN_OPTIONS_STATUS_HIGH_SCORE_VIEW_INIT;Num_demo_levels_seen++;}'):
        if snippet not in flat:
            problems.append('tempopt.c no longer contains: %s' % snippet[:100])
    view_init = flat[flat.index('caseMAIN_OPTIONS_STATUS_HIGH_SCORE_VIEW_INIT:'):
                     flat.index('caseMAIN_OPTIONS_STATUS_HIGH_SCORE_VIEW_MAIN:')]
    if 'break;' in view_init:
        problems.append('tempopt.c HIGH_SCORE_VIEW_INIT no longer falls through into VIEW_MAIN')
    body = code[code.index('Demo_level_table[][3]'):]
    body = body[body.index('{') + 1:body.index('};')]
    source = []
    for match in re.finditer(r'(LEVEL_(\w+)|-[12])\s*,\s*(RES_(\w+)_DAT|-[12])\s*,\s*(LEVEL_(\w+)|-[12])\s*,', body):
        if match.group(1) == '-1':
            break
        if match.group(1) == '-2':
            source.append(None)
            continue
        source.append((match.group(2), match.group(6)))
        theme = re.match(r'[A-Z]+', match.group(2)).group(0)
        if match.group(4) != RESOURCE_NAMES.get(theme, '?') + match.group(2)[len(theme):] + 'DEMO':
            problems.append('Demo_level_table row %s plays %s' % (match.group(2), match.group(4)))
    if source != DEMO_LEVEL_TABLE:
        problems.append('tempopt.c Demo_level_table differs from the transcription')
    hsview = stack.squash(strip_comments((c_root / 'HSView.c').read_text(encoding='latin-1')))
    if ('if(High_score_view_flyon_counter)High_score_view_flyon_counter--;if(High_score_view_flyoff_counter)'
            '{if(!(--High_score_view_flyoff_counter))') not in hsview:
        problems.append('HSView.c HSUpdateFlying differs')
    gamesys = stack.squash(strip_comments((c_root / 'gamesys.C').read_text(encoding='latin-1')))
    if 'if(Game_flags&GAME_FLAG_DEMO_RUNNING){if(Demo_time>0)Demo_time--;}' not in gamesys:
        problems.append('gamesys.C Demo_time count-down differs')
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--c-reference', type=Path, default=frontend.DEFAULT_C,
                        help='frozen C source folder (default: ../froggy/engine/vendor/frogger-psx-src/source)')
    parser.add_argument('--check', action='store_true', help='compare with the committed file instead of writing')
    args = parser.parse_args()
    problems = check_tsv(table_rows())
    trace = attract_pass()
    view_main_calls = trace['view_main_calls']
    expected_rle = [[STATUS_VIEW_INIT, 1], [STATUS_VIEW_MAIN, view_main_calls], [STATUS_VIEW_FINISH, 1],
                    [STATUS_DEMO_INIT, 1 + FLY_TIME + GAME_START_CALLS + 1],
                    [STATUS_DEMO_MAIN, DEMO_FRAMES - DEMO_END_TICKS], [STATUS_DEMO_FADE_OUT, FADE_UNITS],
                    [STATUS_DEMO_FINISH, 1]]
    if trace['c_status_rle'] != expected_rle:
        problems.append('status run lengths %s differ from the measured shape' % trace['c_status_rle'])
    if args.c_reference.is_dir():
        problems += check_c(args.c_reference)
        if not problems:
            print('C cross-check passed against %s' % args.c_reference)
    else:
        print('C source not found at %s; cross-checks skipped' % args.c_reference)
    for problem in problems:
        print('cross-check: ' + problem)
    if problems:
        sys.exit(1)
    text = json.dumps(document(view_main_calls), indent=1, sort_keys=True) + '\n'
    if args.check:
        old = ATTRACT_JSON.read_text(encoding='utf-8') if ATTRACT_JSON.exists() else ''
        if old != text:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                       str(ATTRACT_JSON), 'generated', n=0))
        print('Committed facts differ from the generator' if old != text else 'Committed facts match the generator')
        sys.exit(1 if old != text else 0)
    ATTRACT_JSON.write_text(text, encoding='utf-8')
    print('Wrote %s' % ATTRACT_JSON.relative_to(ROOT))


if __name__ == '__main__':
    main()
