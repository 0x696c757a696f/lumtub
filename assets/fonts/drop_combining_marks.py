# Drops the combining marks (U+0300-U+036F) from NotoSansSC-Regular.ttf's
# character map, leaving its glyphs as they are.
#
# The face has only a few accented Latin letters, but has some lone
# combining marks. Shaping then draws a letter it lacks, such as Polish ś
# or ż, as the bare letter plus one of those marks, which this face does
# not place over the letter. Without the marks the letter is missing as a
# whole and is drawn in the next font that has it.
import sys
from fontTools.ttLib import TTFont

path = sys.argv[1]
font = TTFont(path)
dropped = set()
for table in font['cmap'].tables:
    for cp in [cp for cp in table.cmap if 0x300 <= cp <= 0x36F]:
        del table.cmap[cp]
        dropped.add(cp)
font.save(path)
print('dropped', ' '.join(f'U+{cp:04X}' for cp in sorted(dropped)))
