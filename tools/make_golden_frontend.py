#!/usr/bin/env python3
"""Independent front-end progression and page-flow facts from the frozen C.

Progression replays SelectLevelInit, LevelCompleteStartup/Update and
FrogCollectGoldFrog/SelectLevelCollectGoldFrog over the committed retail
level-select rows. The page flow is the single-player request table, each
row checked against the cited Option_page_request line when the C source is
available. See tests/golden/specs/frontend.md.
"""
import argparse
import difflib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
GOLDEN = ROOT / 'tests' / 'golden'
LEVEL_SELECT_TSV = GOLDEN / 'pc-retail-v3.0e' / 'exe_level_select.tsv'
MUSIC_TSV = GOLDEN / 'pc-retail-v3.0e' / 'exe_music.tsv'
PROGRESS_TSV = GOLDEN / 'pc-retail-v3.0e' / 'frontend_progress.tsv'
FLOW_JSON = GOLDEN / 'synthetic' / 'frontend_flow.json'
DEFAULT_C = ROOT.parent / 'froggy' / 'engine' / 'vendor' / 'frogger-psx-src' / 'source'

COMPLETED, SELECTABLE, ZONEACCESSIBLE = 1, 2, 4

WORLDS = ['CAVES', 'DESERT', 'FOREST', 'JUNGLE', 'ORIGINAL', 'RUINS', 'SWAMP', 'SKY', 'SUBURBIA', 'VOLCANO']
LEVEL_NAMES = [w + s for w in WORLDS for s in ('1', '2', '3', '4', '5', '_MULTI_PLAYER')]
LEVEL = {name: i for i, name in enumerate(LEVEL_NAMES)}
THEMES = ['GEN', 'CAV', 'DES', 'FOR', 'JUN', 'ORG', 'ARN', 'SWP', 'SKY', 'SUB', 'VOL']
GOLD_FROG_THEMES = ['CAV', 'DES', 'FOR', 'JUN', 'ORG', 'SWP', 'SKY', 'SUB', 'VOL']
ALL_GOLD_FROGS = sum(1 << THEMES.index(t) for t in GOLD_FROG_THEMES)
RACE_LEVELS = {LEVEL[w + '_MULTI_PLAYER'] for w in WORLDS}

S, Z = SELECTABLE, ZONEACCESSIBLE
INITIAL_FLAGS = [
    ('ORIGINAL1', S | Z), ('SUBURBIA1', S | Z), ('FOREST1', S | Z), ('VOLCANO1', S | Z),
    ('ORIGINAL2', Z), ('ORIGINAL3', Z), ('ORIGINAL4', Z), ('ORIGINAL5', Z),
    ('SUBURBIA2', Z), ('SUBURBIA3', Z), ('SUBURBIA4', Z), ('SUBURBIA5', Z),
    ('FOREST2', Z), ('VOLCANO2', Z), ('VOLCANO3', Z),
    ('ORIGINAL_MULTI_PLAYER', S | Z), ('SUBURBIA_MULTI_PLAYER', S | Z), ('FOREST_MULTI_PLAYER', S | Z),
    ('VOLCANO_MULTI_PLAYER', S | Z), ('JUNGLE_MULTI_PLAYER', S | Z),
]

P13A, LATER_OPTIONS, LATER_SCORES, LATER_MULTI, LATER_FMV = 'P13a', 'P13c', 'P13d', 'P15', 'P16'
FLOW = [
    ('ANTI_PIRACY', 'timer_elapsed', 'HASBRO_LOGO', LATER_FMV, 'tempopt.c:862', None),
    ('HASBRO_LOGO', 'video_finished', 'LANGUAGE_SELECTION', LATER_FMV, 'tempopt.c:966', 'INTRO'),
    ('LANGUAGE_SELECTION', 'language_detected', 'MAIN_OPTIONS', LATER_FMV, 'tempopt.c:5278', 'CHECK'),
    ('MAIN_OPTIONS', 'start', 'LEVEL_SELECT', P13A, 'tempopt.c:1829', None),
    ('MAIN_OPTIONS', 'race', 'MULTIPLAYER_MODE_OPTIONS', LATER_MULTI, 'tempopt.c:1886', None),
    ('MAIN_OPTIONS', 'options', 'OPTIONS', LATER_OPTIONS, 'tempopt.c:1950', None),
    ('LEVEL_SELECT', 'play', 'GAME', P13A, 'SELECT.C:1424', None),
    ('LEVEL_SELECT', 'back_before_first_play', 'MAIN_OPTIONS', P13A, 'SELECT.C:2046', None),
    ('GAME', 'level_complete', 'LEVEL_COMPLETE', P13A, 'gamesys.C:2729', None),
    ('GAME', 'lives_lost', 'GAME_OVER', P13A, 'gamesys.C:2586', None),
    ('GAME', 'pause_quit', 'GAME_OVER', P13A, 'pause.c:502', None),
    ('GAME', 'jungle_complete_all_gold_frogs', 'OUTRO', LATER_FMV, 'gamesys.C:3956', None),
    ('GAME', 'jungle_complete', 'CREDITS', LATER_FMV, 'gamesys.C:3958', None),
    ('LEVEL_COMPLETE', 'back', 'LEVEL_SELECT', P13A, 'tempopt.c:6033', None),
    ('LEVEL_COMPLETE', 'timeout_zone_complete', 'LEVEL_SELECT', P13A, 'tempopt.c:6054', None),
    ('LEVEL_COMPLETE', 'timeout_next_level', 'GAME', P13A, 'tempopt.c:6059', None),
    ('GAME_OVER', 'timeout', 'CONTINUE', P13A, 'tempopt.c:4124', None),
    ('GAME_OVER', 'confirm', 'CONTINUE', P13A, 'tempopt.c:4131', None),
    ('CONTINUE', 'arcade', 'HIGH_SCORE_INPUT', P13A, 'tempopt.c:3993', None),
    ('CONTINUE', 'race_play_again', 'GAME', LATER_MULTI, 'tempopt.c:3977', None),
    ('CONTINUE', 'race_choose_course', 'LEVEL_SELECT', LATER_MULTI, 'tempopt.c:3981', None),
    ('CONTINUE', 'race_exit', 'MAIN_OPTIONS', LATER_MULTI, 'tempopt.c:3986', None),
    ('HIGH_SCORE_INPUT', 'game_quit', 'MAIN_OPTIONS', P13A, 'hsinput.c:191', None),
    ('HIGH_SCORE_INPUT', 'no_high_score', 'MAIN_OPTIONS', P13A, 'hsinput.c:224', None),
    ('HIGH_SCORE_INPUT', 'entered', 'HIGH_SCORE_VIEW', LATER_SCORES, 'hsinput.c:538', None),
    ('HIGH_SCORE_VIEW', 'back', 'MAIN_OPTIONS', LATER_SCORES, 'HSView.c:868', None),
    ('HIGH_SCORE_VIEW', 'timeout', 'MAIN_OPTIONS', LATER_SCORES, 'HSView.c:928', None),
    ('OUTRO', 'finished', 'CREDITS', LATER_FMV, 'tempopt.c:4252', None),
    ('CREDITS', 'finished', 'HIGH_SCORE_INPUT', LATER_FMV, 'credits.c:882', None),
]
RETAIL_NOTES = {
    'HASBRO_LOGO': 'KF-288: retail HasbroLogoUpdate requests the language page, never INTRO',
    'LANGUAGE_SELECTION': 'KF-351: retail row 5 detects the language silently and requests MAIN_OPTIONS',
}
DIFFERENCES = [
    {'topic': 'start page', 'source': 'VERSION (OPTIONS.H enum, PSX ANTI_PIRACY only)',
     'retail': 'ANTI_PIRACY is the seeded first page', 'followed': 'retail', 'reference': 'KF-294, KF-343'},
    {'topic': 'boot order', 'source': 'HASBRO_LOGO -> INTRO -> CHECK -> MAIN_OPTIONS',
     'retail': 'ANTI_PIRACY -> HASBRO_LOGO -> LANGUAGE_SELECTION -> MAIN_OPTIONS', 'followed': 'retail',
     'reference': 'KF-288, KF-343, KF-351'},
    {'topic': 'page numbers', 'source': 'vendored OPTIONS.H enum',
     'retail': '+1 through the boot range, +2 from LEVEL_SELECT', 'followed': 'names only, no numbers',
     'reference': 'KF-147, KF-254, KF-288'},
    {'topic': 'escape key', 'source': 'ESC requests OPTIONS_PAGE_EXIT (OPTIONS.C:189, SELECT.C:2098/2408)',
     'retail': 'ESC is a pressed-edge back key ORed into the TRIANGLE back-outs; quit is Alt+F4',
     'followed': 'retail', 'reference': 'KF-250, KF-368'},
    {'topic': 'level select back-out', 'source': 'Sel_first_time = TRUE in MainOptionsShutdown (tempopt.c:2006)',
     'retail': 'KF-250 says Sel_first_time is never written TRUE, making the back-out dead',
     'followed': 'frozen C: back-out live until the first play after the main menu', 'reference': 'KF-250'},
]


def read_tsv(path):
    rows = []
    for line in path.read_text(encoding='utf-8').splitlines():
        if line and not line.startswith('#'):
            rows.append(line.split('\t'))
    return rows


def read_stacks(path):
    stacks = {'arcade': [], 'race': []}
    for row in read_tsv(path):
        level = int(row[2])
        if level == -1:
            continue
        stacks[row[0]].append({'level': level, 'world': int(row[3]), 'stack': int(row[4]), 'theme': int(row[5])})
    return stacks


class Progress:
    """SEL_LEVEL_INFO li_library_id/li_flags plus Gold_frogs, as the C keeps them."""

    def __init__(self, stacks):
        self.rows = {name: [dict(r, flags=0) for r in rows] for name, rows in stacks.items()}
        self.gold_frogs = 0
        for name, flags in INITIAL_FLAGS:
            self.set_flags(LEVEL[name], flags)

    def _list(self, level):
        return self.rows['race' if level in RACE_LEVELS else 'arcade']

    def set_flags(self, level, flags):
        for row in self._list(level):
            if row['level'] == level:
                row['flags'] = flags
                return

    def flags_for(self, level):
        for row in self._list(level):
            if row['level'] == level:
                return row['flags']
        if LEVEL['JUNGLE1'] <= level <= LEVEL['JUNGLE2']:
            for row in self.rows['arcade']:
                if LEVEL['JUNGLE1'] <= row['level'] <= LEVEL['JUNGLE2']:
                    return row['flags']
        raise ValueError('level %d is not in the stack' % level)

    def complete_level(self, level):
        """LevelCompleteStartup's arcade arm; returns the next level of the world or -1."""
        self.set_flags(level, COMPLETED | SELECTABLE | ZONEACCESSIBLE)
        arcade = self.rows['arcade']
        index = next((i for i, row in enumerate(arcade) if row['level'] == level), None)
        if index is None:
            return -1
        following = -1
        if index + 1 == len(arcade):
            if arcade[index]['level'] == LEVEL['JUNGLE1']:
                arcade[index]['level'] = LEVEL['JUNGLE2']
        elif arcade[index]['world'] == arcade[index + 1]['world']:
            following = arcade[index + 1]['level']
        return following

    def open_level(self, level, arm):
        """LevelCompleteUpdate: the count-down arm always writes, TRIANGLE only when closed."""
        if arm == 'countdown' or not self.flags_for(level) & SELECTABLE:
            self.set_flags(level, SELECTABLE | ZONEACCESSIBLE)

    def collect_gold_frog(self, theme):
        """FrogCollectGoldFrog's guard and bit, then SelectLevelCollectGoldFrog."""
        if self.gold_frogs & (1 << theme):
            return -1
        self.gold_frogs |= 1 << theme
        arcade = self.rows['arcade']
        i = 0
        while i < len(arcade):
            group_theme, first_level, open_world = arcade[i]['theme'], arcade[i]['level'], False
            while i < len(arcade) and arcade[i]['theme'] == group_theme:
                open_world = open_world or bool(arcade[i]['flags'] & SELECTABLE)
                i += 1
            if not open_world:
                for row in arcade:
                    if row['theme'] == group_theme:
                        self.set_flags(row['level'], ZONEACCESSIBLE)
                self.set_flags(first_level, SELECTABLE | ZONEACCESSIBLE)
                return first_level
        return -1

    def levels(self):
        return ','.join(str(r['level']) for r in self.rows['arcade'])

    def flags(self):
        return ','.join(str(r['flags']) for r in self.rows['arcade'])


def progress_text(stacks, codes):
    out = ['# Front-end progression facts; schema in tests/golden/specs/frontend.md.']
    out.append('#constant\tname\tvalue')
    for name, value in (('COMPLETED', COMPLETED), ('SELECTABLE', SELECTABLE),
                        ('ZONEACCESSIBLE', ZONEACCESSIBLE), ('ALL_GOLD_FROGS', ALL_GOLD_FROGS)):
        out.append('constant\t%s\t%d' % (name, value))
    fresh = Progress(stacks)
    out.append('#initial\tlist\tposition\tlevel\tcode\tflags')
    for name in ('arcade', 'race'):
        for position, row in enumerate(fresh.rows[name]):
            out.append('initial\t%s\t%d\t%d\t%s\t%d' % (name, position, row['level'], codes[row['level']], row['flags']))
    progress = Progress(stacks)
    out.append('#complete\tstep\tlevel\tcode\tnext_level\tlevels\tflags')
    for step, row in enumerate(stacks['arcade']):
        following = progress.complete_level(row['level'])
        if following != -1:
            progress.open_level(following, 'triangle')
        out.append('complete\t%d\t%d\t%s\t%d\t%s\t%s' % (
            step, row['level'], codes[row['level']], following, progress.levels(), progress.flags()))
    out.append('#replay\tarm\tlevel\tnext_level\tflags')
    for arm in ('triangle', 'countdown'):
        replay = Progress(stacks)
        world = stacks['arcade'][0]['world']
        for row in stacks['arcade']:
            if row['world'] == world:
                following = replay.complete_level(row['level'])
                if following != -1:
                    replay.open_level(following, arm)
        first = stacks['arcade'][0]['level']
        following = replay.complete_level(first)
        replay.open_level(following, arm)
        out.append('replay\t%s\t%d\t%d\t%s' % (arm, first, following, replay.flags()))
    out.append('#lookup\tlevel\tflags')
    for level in (LEVEL['JUNGLE1'], LEVEL['JUNGLE2']):
        out.append('lookup\t%d\t%d' % (level, progress.flags_for(level)))
    progress = Progress(stacks)
    themes = []
    for row in stacks['arcade']:
        if row['theme'] not in themes:
            themes.append(row['theme'])
    themes.append(themes[0])
    out.append('#gold_frog\tstep\ttheme\tgold_frogs\topened_level\tflags')
    for step, theme in enumerate(themes):
        opened = progress.collect_gold_frog(theme)
        out.append('gold_frog\t%d\t%d\t%d\t%d\t%s' % (step, theme, progress.gold_frogs, opened, progress.flags()))
    return '\n'.join(out) + '\n'


def flow_document():
    transitions = []
    for page, event, target, phase, source, source_next in FLOW:
        item = {'page': page, 'event': event, 'next': target, 'phase': phase, 'source': source}
        if source_next is not None:
            item['source_next'] = source_next
            item['retail'] = RETAIL_NOTES[page]
        transitions.append(item)
    pages = []
    for page, _, target, *_ in FLOW:
        for name in (page, target):
            if name not in pages:
                pages.append(name)
    return {'start_page': 'ANTI_PIRACY', 'p13a_start_page': 'MAIN_OPTIONS', 'pages': pages,
            'transitions': transitions, 'differences': DIFFERENCES}


def flow_text():
    return json.dumps(flow_document(), indent=1) + '\n'


def check_c(c_root, stacks):
    """Compare the transcriptions above with the frozen C; returns problems."""
    problems = []
    library = (c_root / 'LIBRARY.H').read_text(encoding='latin-1')
    names = re.findall(r'^\s*LEVEL_(\w+),', library, re.M)[:len(LEVEL_NAMES)]
    if names != LEVEL_NAMES:
        problems.append('LIBRARY.H level enum differs from the transcription')
    gamesys_h = (c_root / 'gamesys.H').read_text(encoding='latin-1')
    themes = re.findall(r'^\s*THEME_(\w+),', gamesys_h, re.M)[:len(THEMES)]
    if themes != THEMES:
        problems.append('gamesys.H theme enum differs from the transcription')
    ent_gen = (c_root / 'ent_gen.h').read_text(encoding='latin-1')
    gold = re.findall(r'#define\s+GEN_GOLD_FROG_\d\s+\(1<<THEME_(\w+)\)', ent_gen)
    if sorted(gold) != sorted(GOLD_FROG_THEMES):
        problems.append('ent_gen.h gold frog bits differ: %s' % gold)
    select_h = (c_root / 'SELECT.H').read_text(encoding='latin-1')
    for name, value in (('COMPLETED', COMPLETED), ('SELECTABLE', SELECTABLE), ('ZONEACCESSIBLE', ZONEACCESSIBLE)):
        if not re.search(r'#define\s+SEL_LF_%s\s+\(1<<%d\)' % (name, value.bit_length() - 1), select_h):
            problems.append('SELECT.H SEL_LF_%s differs' % name)
    select = (c_root / 'SELECT.C').read_text(encoding='latin-1')
    init = select[select.index('MR_VOID\tSelectLevelInit(MR_VOID)'):]
    init = init[:init.index('Sel_arcade_level_ptr\t= SelectGetLevelPointer')]
    calls = re.findall(r'SelectSetLevelFlags\(LEVEL_(\w+),\s*([A-Z_ |]+)\);', init)
    parsed = [(n, sum({'SEL_LF_SELECTABLE': S, 'SEL_LF_ZONEACCESSIBLE': Z}[f.strip()] for f in flags.split('|')))
              for n, flags in calls]
    if parsed != INITIAL_FLAGS:
        problems.append('SelectLevelInit flags differ from the transcription')
    arcade = select[select.index('Sel_arcade_levels[] ='):select.index('Sel_race_levels[] =')]
    source_rows = re.findall(r'^\s*LEVEL_(\w+),\s*SEL_WORLD_ID_\w+,\s*(\d+),\s*THEME_(\w+),', arcade, re.M)
    want = [(LEVEL_NAMES[r['level']], r['theme']) for r in stacks['arcade']]
    got = [(n, THEMES.index(t)) for n, _, t in source_rows]
    if got != want:
        problems.append('source arcade stack differs from the retail table rows')
    if [int(p) for _, p, _ in source_rows] != [r['stack'] for r in stacks['arcade']]:
        problems.append('source arcade stack positions differ from the retail rows')
    for page, event, target, _, source, source_next in FLOW:
        file_name, line = source.split(':')
        text = (c_root / file_name).read_text(encoding='latin-1').splitlines()[int(line) - 1]
        expected = source_next or target
        if not re.search(r'(Option_page_request|High_score_view_delayed_request)\s*=\s*OPTIONS_PAGE_%s\s*;' % expected, text) \
                or text.lstrip().startswith('//'):
            problems.append('%s %s: %s does not request %s' % (page, event, source, expected))
    if 'Sel_first_time = TRUE;' not in (c_root / 'tempopt.c').read_text(encoding='latin-1').splitlines()[2005]:
        problems.append('tempopt.c:2006 no longer sets Sel_first_time')
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--c-reference', type=Path, default=DEFAULT_C,
                        help='frozen C source folder (default: ../froggy/engine/vendor/frogger-psx-src/source)')
    parser.add_argument('--check', action='store_true', help='compare with the committed files instead of writing')
    args = parser.parse_args()
    stacks = read_stacks(LEVEL_SELECT_TSV)
    codes = {int(r[0]): r[1] for r in read_tsv(MUSIC_TSV)}
    if len(stacks['arcade']) != 33 or len(stacks['race']) != 5:
        sys.exit('unexpected level-select row counts %d/%d' % (len(stacks['arcade']), len(stacks['race'])))
    if args.c_reference.is_dir():
        problems = check_c(args.c_reference, stacks)
        for problem in problems:
            print('C cross-check: ' + problem)
        if problems:
            sys.exit(1)
        print('C cross-check passed against %s' % args.c_reference)
    else:
        print('C source not found at %s; cross-checks skipped' % args.c_reference)
    outputs = {PROGRESS_TSV: progress_text(stacks, codes), FLOW_JSON: flow_text()}
    failed = False
    for path, text in outputs.items():
        if args.check:
            old = path.read_text(encoding='utf-8') if path.exists() else ''
            if old != text:
                failed = True
                sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                           str(path), 'generated', n=0))
        else:
            path.write_text(text, encoding='utf-8')
            print('Wrote %s' % path.relative_to(ROOT))
    if args.check:
        print('Committed facts differ from the generator' if failed else 'Committed facts match the generator')
        sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
