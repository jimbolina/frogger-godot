#!/usr/bin/env python3
"""Independent modern-profile map and sky UVs from synthetic C texture records.

Retail arithmetic, from the frozen C:
- mapload.C ResolveMapPolys: a polygon's stored UV byte b becomes the pixel
  (b * size) // 255 stored back into a byte; a static polygon then adds the
  image's page position (te_u0, te_v0) into that byte. Size is the image's
  in-game size, as the map texture contract states; fixtures keep HIT flags
  off ordinary polygons.
- mapdisp.c MapUpdateAnimatedPolys: each update increments the UV counter;
  equal to the duration it zeroes the packed offset and the counter, else it
  adds du | dv << 8 to the packed 16-bit offset (U carries into V). Texture
  tracks advance the cel when their counter reaches the period, wrapping to
  cel 0. A target's page byte is base + (te_u0 + offset) in byte arithmetic.
- mapdisp.c MapRenderQuads ENVMAP: page byte (vertex + short(-camera)) >> 5 + 128.
- MR_VRAM.C and the sky set-up in mapdisp.c: sky corners are (u, v),
  (u + w', v), (u, v + h'), (u + w', v + h') with w' = w - HIT_X and
  h' = h - HIT_Y, assigned to the polygon corners by rotation.
- VLO padding: an image of in-game size w inside a padded upload of size W
  sits at page u = vram_x % 256 + (W - w) // 2.

Modern mapping: every coordinate is normalised inside the padded image,
(page byte - vram_x % 256) / W, which is the texel the page held measured
from the padded upload's corner. Environment UVs drop the floor and the byte
wrap: (vertex + short(-camera)) / 32 + 128 replaces the page byte. Sky tiles
sample layer L, the first-seen index of their texture in row-major tile order.
'sampled' is the fractional part of 'uv', the texel repeat sampling reads;
'retail_texel' is the retail page byte measured from the same corner.
"""
import argparse
import json
import math
from pathlib import Path

SCHEMA = 'map-modern-uv-v1'
TOLERANCE = 1e-6
HIT_X, HIT_Y, REFERENCED, BLACK_KEY, SPRITE = 1 << 2, 1 << 3, 1 << 4, 1 << 5, 1 << 15
FT4, ENVMAP = 3, 2
ANIM_UV, ANIM_TEXTURE = 1, 2
FULL = [[0, 0], [255, 0], [0, 255], [255, 255]]
FLAT = [[0, 0, 0], [256, 0, 0], [0, 0, -256], [256, 0, -256]]
ENV_CORNERS = [[-1000, 0, 2000], [1500, 0, 2000], [5000, 0, -700], [-3300, 0, 900]]
ENV_CAMERAS = [[0, 0, 0], [-1000.5, -2500, 2000.25], [40000.5, 0, -1234.75]]
ROTATIONS = [[0, 1, 2, 3], [2, 0, 3, 1], [3, 2, 1, 0], [1, 3, 0, 2]]


def image(texture_id, vram_x, vram_y, width, height, pad, flags=SPRITE):
    padded_width, padded_height = width + 2 * pad, height + 2 * pad
    return dict(texture_id=texture_id, vram_x=vram_x, vram_y=vram_y, padded_width=padded_width,
                padded_height=padded_height, width=width, height=height, flags=flags,
                u=(vram_x % 256 + pad) & 255, v=(vram_y % 256 + pad) & 255)


def polygon(texture, uv_bytes, flags=0, corners=FLAT):
    return dict(texture=texture, uv_bytes=uv_bytes, flags=flags, corners=corners)


FIXTURES = [
    dict(name='edge_byte_255',
         note='Byte 255 on a 64-wide image reaches u == width, the first right padding column; on a 256-wide '
              'image it wraps to 0 as the C byte store does; middle bytes truncate.',
         images=[image(501, 0, 0, 64, 64, 4), image(502, 0, 256, 256, 256, 0)],
         polygons=[polygon(0, FULL), polygon(1, FULL), polygon(0, [[1, 2], [128, 64], [254, 253], [127, 255]])]),
    dict(name='environment_page_256',
         note='A pad 1 ENVMAP image filling its page at page x 0 (254 wide, HIT_X as retail): repeat sampling '
              'every 256 texels reproduces the page.',
         images=[image(503, 0, 512, 254, 254, 1, SPRITE | REFERENCED | HIT_X)],
         polygons=[polygon(0, FULL, ENVMAP, ENV_CORNERS)], cameras=ENV_CAMERAS),
    dict(name='environment_page_255',
         note='The texture 1465 case: 253 wide padded to 255, so modern repeats every 255 texels where the '
              'retail page byte repeats every 256.',
         divergence='repeat_255',
         images=[image(504, 0, 768, 253, 253, 1, SPRITE | REFERENCED | BLACK_KEY)],
         polygons=[polygon(0, FULL, ENVMAP, ENV_CORNERS)], cameras=ENV_CAMERAS),
    dict(name='negative_dv_scroll',
         note='dv = -1 is byte 255 added at bit 8: V steps back one row per update and the duration resets it.',
         images=[image(505, 64, 1124, 32, 32, 2)],
         polygons=[polygon(0, [[0, 128], [255, 128], [0, 255], [255, 255]])],
         animation=dict(type=ANIM_UV, du=0, dv=-1, uv_duration=16, cel_period=0, cels=[], target=0),
         ticks=[0, 1, 7, 14, 15, 16]),
    dict(name='scroll_beyond_image',
         note='The SWP5_WIN95 texture 1456 case: the scroll leaves the image; retail samples the neighbouring '
              'page pixels, modern wraps within the image.',
         divergence='wraps_within_image',
         images=[image(506, 128, 1280, 16, 16, 2)],
         polygons=[polygon(0, FULL)],
         animation=dict(type=ANIM_UV, du=4, dv=0, uv_duration=0, cel_period=0, cels=[], target=0),
         ticks=[0, 3, 10, 40]),
    dict(name='cels_of_different_sizes',
         note='The base pixels come from the polygon\'s own 32 x 32 image; each cel normalises them inside its '
              'own padded size and page position.',
         images=[image(507, 0, 1536, 32, 32, 2), image(508, 100, 1792, 64, 48, 4), image(509, 40, 1536, 40, 36, 2)],
         polygons=[polygon(0, FULL)],
         animation=dict(type=ANIM_TEXTURE, du=0, dv=0, uv_duration=0, cel_period=2, cels=[0, 1, 2], target=0),
         ticks=[0, 1, 2, 3, 4, 5]),
]

SKY = dict(
    name='sky_hit_x_rotations',
    note='A HIT_X tile in all four rotations, a plain tile and a HIT_X | HIT_Y tile, in row-major order.',
    images=[image(601, 216, 2048, 32, 32, 4, SPRITE | HIT_X), image(602, 0, 2048, 32, 32, 4),
            image(603, 216, 2264, 32, 32, 4, SPRITE | HIT_X | HIT_Y)],
    dimensions=[3, 2],
    tiles=[0, 0, 0, 0, 1, 2],
    rotations=[0, 1, 2, 3, 1, 2],
)


def short(value):
    return (value + 32768) % 65536 - 32768


def resolve(byte, size):
    """ResolveMapPolys: integer pixel stored back into a byte."""
    return (byte * size // 255) & 255


def normalised(page, origin, padded):
    return (page - origin % 256) / padded


def rounded(values):
    return [round(v, 12) for v in values]


def corner_state(page_u, page_v, retail_u, retail_v, img):
    uv = [normalised(page_u, img['vram_x'], img['padded_width']), normalised(page_v, img['vram_y'], img['padded_height'])]
    return dict(uv=rounded(uv), sampled=rounded([c - math.floor(c) for c in uv]),
                retail_texel=[retail_u - img['vram_x'] % 256, retail_v - img['vram_y'] % 256])


def state(corners, **extra):
    result = dict(extra)
    for key in ('uv', 'sampled', 'retail_texel'):
        result[key] = [c[key] for c in corners]
    return result


def static_states(fixture, poly):
    img = fixture['images'][poly['texture']]
    corners = []
    for byte_u, byte_v in poly['uv_bytes']:
        page_u = (resolve(byte_u, img['width']) + img['u']) & 255
        page_v = (resolve(byte_v, img['height']) + img['v']) & 255
        corners.append(corner_state(page_u, page_v, page_u, page_v, img))
    return [state(corners, tick=0)]


def environment_states(fixture, poly):
    img = fixture['images'][poly['texture']]
    states = []
    for camera in fixture['cameras']:
        corners = []
        for x, _y, z in poly['corners']:
            vec_x = x + short(-camera[0])
            vec_z = z + short(-camera[2])
            if abs(vec_x) > 32767 or abs(vec_z) > 32767:
                raise SystemExit('Environment fixture leaves the C short range')
            retail_u = (math.floor(vec_x / 32) + 128) & 255
            retail_v = (math.floor(vec_z / 32) + 128) & 255
            corners.append(corner_state(vec_x / 32 + 128, vec_z / 32 + 128, retail_u, retail_v, img))
        states.append(state(corners, tick=0, camera=camera))
    return states


def animated_states(fixture, poly):
    track = fixture['animation']
    images = fixture['images']
    original = images[poly['texture']]
    base = [(resolve(u, original['width']), resolve(v, original['height'])) for u, v in poly['uv_bytes']]
    offset, uv_count, cel_count, cel, texture = 0, 0, 0, 0, poly['texture']
    states = []
    for update in range(1, max(fixture['ticks']) + 2):
        if track['type'] & ANIM_UV:
            uv_count = (uv_count + 1) & 65535
            if uv_count == track['uv_duration']:
                offset, uv_count = 0, 0
            else:
                offset = (offset + (track['du'] & 255) + ((track['dv'] & 255) << 8)) & 65535
        if track['type'] & ANIM_TEXTURE:
            cel_count = (cel_count + 1) & 65535
            if cel_count >= track['cel_period']:
                cel_count = 0
                cel = (cel + 1) & 65535
                if cel == len(track['cels']):
                    cel = 0
                texture = track['cels'][cel]
        tick = update - 1
        if tick not in fixture['ticks']:
            continue
        img = images[texture]
        bu = (img['u'] + (offset & 255)) & 255
        bv = (img['v'] + (offset >> 8)) & 255
        corners = []
        for base_u, base_v in base:
            page_u, page_v = (base_u + bu) & 255, (base_v + bv) & 255
            corners.append(corner_state(page_u, page_v, page_u, page_v, img))
        states.append(state(corners, tick=tick, texture=texture, offset=[offset & 255, offset >> 8]))
    return states


def map_fixture(fixture):
    polygons = []
    for index, poly in enumerate(fixture['polygons']):
        if poly['flags'] & ENVMAP:
            states = environment_states(fixture, poly)
        elif fixture.get('animation') and fixture['animation']['target'] == index:
            states = animated_states(fixture, poly)
        else:
            states = static_states(fixture, poly)
        polygons.append(dict(poly, states=states))
    result = {key: value for key, value in fixture.items() if key not in ('polygons', 'cameras')}
    result['kind'] = 'map'
    result['polygons'] = polygons
    return result


def sky_fixture(sky):
    layers = []
    tiles = []
    for texture, rotation in zip(sky['tiles'], sky['rotations']):
        if texture not in layers:
            layers.append(texture)
        img = sky['images'][texture]
        span_u = img['width'] - (1 if img['flags'] & HIT_X else 0)
        span_v = img['height'] - (1 if img['flags'] & HIT_Y else 0)
        corners = [(img['u'], img['v']), ((img['u'] + span_u) & 255, img['v']),
                   (img['u'], (img['v'] + span_v) & 255), ((img['u'] + span_u) & 255, (img['v'] + span_v) & 255)]
        uv = []
        for corner in ROTATIONS[rotation]:
            page_u, page_v = corners[corner]
            uv.append(rounded([normalised(page_u, img['vram_x'], img['padded_width']),
                               normalised(page_v, img['vram_y'], img['padded_height'])]))
        tiles.append(dict(texture=texture, rotation=rotation, layer=layers.index(texture), uv=uv))
    return dict(kind='sky', name=sky['name'], note=sky['note'], images=sky['images'],
                dimensions=sky['dimensions'], layer_count=len(layers), tiles=tiles)


def facts():
    return dict(schema=SCHEMA, tolerance=TOLERANCE,
                fixtures=[map_fixture(f) for f in FIXTURES] + [sky_fixture(SKY)])


def main():
    """Verify the committed facts by default; rewrite only with an explicit flag."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('output', type=Path)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = json.dumps(facts(), indent=1) + '\n'
    if args.write:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
        print(f'Modern map UV facts written to {args.output}')
        return
    if not args.output.exists() or args.output.read_text(encoding='utf-8') != text:
        raise SystemExit(f'Modern map UV facts in {args.output} differ; use --write only to deliberately regenerate')
    print('Modern map UV facts verified')


if __name__ == '__main__':
    main()
