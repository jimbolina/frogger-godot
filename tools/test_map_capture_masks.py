"""Asset-free tests for declared raster boundaries; run with Python directly."""
import json
from pathlib import Path
import tempfile
import unittest
import sys
sys.dont_write_bytecode = True
from PIL import Image
import compare_map_captures as comparison
from make_map_capture_masks import clip_segment, signed_area


class RasterMasksTest(unittest.TestCase):
    def test_source_geometry_boundaries(self):
        self.assertGreater(signed_area([0,0], [10,0], [0,10]), 0)
        self.assertEqual(clip_segment([-10,100], [20,100]), [[0,100],[20,100]])
        self.assertIsNone(clip_segment([-10,-10], [-5,-5]))
        eligible = comparison.shape_mask((100,100), [{'rect':[10,0,100,100]}])
        mask = comparison.reference_edges(eligible)
        self.assertEqual(mask.getpixel((8,50)), 255)
        self.assertEqual(mask.getpixel((12,50)), 255)
        self.assertEqual(mask.getpixel((13,50)), 0)

    def test_texture_stripes_remain_compared(self):
        with tempfile.TemporaryDirectory(prefix='frogger-raster-mask-') as directory:
            root = Path(directory)
            reference = Image.new('RGB', (100,100))
            reference.putdata([(255,255,255) if x%2 else (0,0,0)
                               for y in range(100) for x in range(100)])
            reference.save(root/'reference.png')
            reference.save(root/'candidate.png')
            declaration = {'eligible_terrain':[{'rect':[10,0,100,100]}],
                           'include':[{'rect':[0,0,100,100]}], 'exclude':[],
                           'raster_edge_policy':'eligible_union_silhouette', 'landmarks':[]}
            (root/'masks.json').write_text(json.dumps(declaration))
            metrics = comparison.compare(root/'reference.png', root/'candidate.png',
                                         root/'masks.json', root/'output')
            self.assertEqual(metrics['reference_edge_exclusion_pixels'], 300)
            self.assertEqual(metrics['compared_pixels'], 8700)
            self.assertEqual(metrics['passing_fraction'], 1.0)


if __name__ == '__main__':
    unittest.main()
