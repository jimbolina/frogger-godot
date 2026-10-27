#!/usr/bin/env python3
"""Independent callback facts from frozen ent_org/sub/swp/sky/jun C bodies."""
import argparse
import json
from pathlib import Path

OUTPUT = Path(__file__).resolve().parents[1] / 'tests/golden/synthetic/script_callbacks.json'
SOUNDS = {
    'FROG_TRAFFIC_SPLAT': [13], 'LOG_SPLASH': [19], 'HIT_TURTLE': [14, 15],
    'SWP_OIL_DRUM': [108], 'SWP_PALLET': [15], 'SWP_SUNKCAR': [14],
    'SWP_STAT_PIPE': [108], 'SWP_STAT_PIPE_BIG_STR': [108],
    'SKY_BIRD1_CALL': [128], 'SKY_BIRD2_CALL': [132], 'SKY_BIRD3_CALL': [134],
    'SKY_BIRD4_CALL': [147], 'SKY_FROG_HELICOPTER': [141],
    'SUB_LILLY_PAD': [15], 'JUN_HIPPO_HIT': [], 'SWP_RACCOON': [109, 19],
    'SWP_PELICAN_CALL': [120], 'SKY_HOMING_BIRD': [139], 'SKY_BALLOON': [149],
}


def facts():
    """Exercise source callback gating and the two path-height colour callbacks."""
    rows = []
    for name, sounds in SOUNDS.items():
        for hit in (False, True):
            for displayed in (False, True):
                rows.append(dict(name='SCRIPT_CB_' + name, hit=hit, no_display=not displayed,
                                 path_y=0, sounds=sounds if hit else [],
                                 colours=[0, 0, 0], ambient=[0, 0, 0]))
    for name in ('JUN_PIRANAHA', 'SWP_MUTANT_FISH'):
        for hit in (False, True):
            for displayed in (False, True):
                for height in (-1, 0, 1):
                    colours = ambient = [0, 0, 0]
                    if hit and displayed:
                        if name == 'JUN_PIRANAHA':
                            colours = [64, 96, 160] if height == 0 else [128, 128, 128]
                            ambient = [64, 64, 208] if height == 0 else [64, 64, 64]
                        else:
                            colours = [64, 160, 96] if height == 0 else [128, 128, 128]
                            ambient = [64, 64, 64] if height == 0 else [64, 208, 64]
                    rows.append(dict(name='SCRIPT_CB_' + name, hit=hit, no_display=not displayed,
                                     path_y=height, sounds=[], colours=colours, ambient=ambient))
    for height in (-256, -1, 0, 127, 128, 256):
        for displayed in (False, True):
            for name in ('DIVE_COLOUR_CHANGE', 'JUN_HIPPO_DIVE', 'VOL_MECHANISM'):
                colours = ambient = [0, 0, 0]
                deaths = []
                no_fade = False
                if displayed:
                    if name == 'DIVE_COLOUR_CHANGE':
                        red = max(0, 64 - (height >> 2))
                        blue = max(0, 96 - (height >> 2))
                        packed = (blue << 16) + (red << 8) + red
                        colours = [(packed >> shift) & 255 for shift in (0, 8, 16)]
                        ambient = [32, 240, 160]
                        no_fade = True
                    elif name == 'JUN_HIPPO_DIVE':
                        red = min(192 - height, 255)
                        blue = min(191 + height, 255)
                        packed = (blue << 16) + (red << 8) + red
                        colours = [(packed >> shift) & 255 for shift in (0, 8, 16)]
                        ambient = [64, 64, 192]
                        deaths = [8] if height >= 128 else []
                        no_fade = True
                    elif abs(height) < 32:
                        deaths = [2]
                rows.append(dict(name='SCRIPT_CB_' + name, hit=True, no_display=not displayed,
                                 path_y=0, has_path=name != 'DIVE_COLOUR_CHANGE', deviation=height,
                                 carry=True, sounds=[], colours=colours, ambient=ambient,
                                 deaths=deaths, no_fade=no_fade))
    for hit in (False, True):
        rows.append(dict(name='SCRIPT_CB_SKY_HELIUM_BALLOON', hit=hit, no_display=False,
                         path_y=0, sounds=[], colours=[0, 0, 0], ambient=[0, 0, 0],
                         program=2 if hit else 1))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = json.dumps(facts(), indent=2) + '\n'
    if args.write:
        OUTPUT.write_text(text, encoding='utf-8')
    elif OUTPUT.read_text(encoding='utf-8') != text:
        raise ValueError('Callback facts differ from independent source model')
    print('Script callback facts verified against independent Python source model.')


if __name__ == '__main__':
    main()
