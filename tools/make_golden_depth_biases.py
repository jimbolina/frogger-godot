#!/usr/bin/env python3
"""Independent gameplay depth biases from frozen C ordering-table offsets.

Constants are transcribed from gamesys.H, API.SRC/MR_VIEW.H and MR_VIEW.C,
mapdisp.H/mapdisp.c, FROG.H/FROG.C, API.SRC/MR_ANIM.C, PARTICLE.H/PARTICLE.C
and API.SRC/MR_SPRT.C. A bias is in game units of view depth (SZ); positive
values move an object toward the camera.
"""
import argparse
import json
from pathlib import Path

OUTPUT = Path(__file__).resolve().parents[1] / 'tests/golden/synthetic/depth_biases.json'

MR_VP_SIZE_4096 = 12
MR_VP_VIEWDIST_8192 = 2
MAP_POLY_OT_OFFSET = 64
FROG_GLOBAL_OT_OFFSET = -0x30
PICKUP_OT_OFFSET = -0x10
FIREFLY_SC_OT_OFFSET = 0


def viewport():
    """Single-player gameplay viewport: ordering-table slots, view distance and otz shift."""
    slots = 1 << MR_VP_SIZE_4096
    view_distance = 1 << (15 - MR_VP_VIEWDIST_8192)
    otz_shift = 15 - MR_VP_VIEWDIST_8192 - MR_VP_SIZE_4096
    return slots, view_distance, otz_shift


def toward_camera_after_shift(slot_offset, otz_shift):
    """Game units nearer for a slot offset added after `otz >>= otz_shift`; later slots draw first."""
    return -(slot_offset << otz_shift)


def toward_camera_before_shift(depth_offset):
    """Game units nearer for an offset added to view depth before the shift."""
    return -depth_offset


def facts():
    slots, view_distance, otz_shift = viewport()
    terrain = toward_camera_after_shift(MAP_POLY_OT_OFFSET, otz_shift)
    frog = toward_camera_before_shift(FROG_GLOBAL_OT_OFFSET)
    pickup = toward_camera_after_shift(PICKUP_OT_OFFSET, otz_shift)
    firefly = toward_camera_after_shift(FIREFLY_SC_OT_OFFSET, otz_shift)
    return dict(
        schema='depth-biases-v1',
        viewport=dict(ot_slots=slots, view_distance=view_distance, otz_shift=otz_shift),
        terrain_back=-terrain,
        frog_forward=frog,
        pickup_forward=pickup,
        firefly_forward=firefly,
        terrain_hides=dict(frog=frog - terrain, pickup=pickup - terrain, firefly=firefly - terrain, model=-terrain),
    )


def main():
    """Verify reproducibility by default; rewrite only with an explicit flag."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = json.dumps(facts(), indent=2) + '\n'
    if args.write:
        OUTPUT.write_text(text)
    elif not OUTPUT.exists() or OUTPUT.read_text() != text:
        raise SystemExit('Depth bias facts differ; use --write only to deliberately regenerate')
    print('Depth bias facts verified')


if __name__ == '__main__':
    main()
