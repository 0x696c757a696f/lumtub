# Builds LumtubBlank-Regular.ttf: empty, zero-width glyphs for invisible
# characters that iOS would draw as a box (no font of its own maps them).
import sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
cps = set()
cps.update([0x115F, 0x1160, 0x3164, 0xFFA0])          # Hangul fillers
cps.update([0x180E, 0x200B, 0x2060, 0x2061, 0x2062, 0x2063, 0x2064, 0xFEFF])
cps.update(range(0x2065, 0x206A))                       # reserved invisibles
cps.update(range(0x206A, 0x2070))                       # deprecated format chars
cps.update([0x061C, 0x200E, 0x200F])                    # direction marks
cps.update(range(0x202A, 0x202F))                       # embeddings/overrides
cps.update(range(0x2066, 0x206A))                       # isolates
cps.update([0xE0001])                                   # language tag
cps.update(range(0xFFF0, 0xFFF9))                       # unassigned specials
cps.update(range(0x1BCA0, 0x1BCA4))                     # shorthand format controls
cps.update(range(0x1D173, 0x1D17B))                     # musical format controls
fb = FontBuilder(1000, isTTF=True)
fb.setupGlyphOrder(['.notdef', 'blank'])
fb.setupCharacterMap({cp: 'blank' for cp in sorted(cps)})
pen = TTGlyphPen(None)
empty = pen.glyph()
fb.setupGlyf({'.notdef': empty, 'blank': TTGlyphPen(None).glyph()})
fb.setupHorizontalMetrics({'.notdef': (0, 0), 'blank': (0, 0)})
fb.setupHorizontalHeader(ascent=880, descent=-120)
fb.setupNameTable({'familyName': 'Lumtub Blank', 'styleName': 'Regular', 'copyright': 'Lumtub (no outlines)'})
fb.setupOS2(sTypoAscender=880, sTypoDescender=-120, usWinAscent=880, usWinDescent=120)
fb.setupPost()
fb.save(sys.argv[1])
print(len(cps), 'code points')
