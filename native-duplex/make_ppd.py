#!/usr/bin/env python3
"""Preserve HP driver settings; wrap only the raster conversion rule."""
import gzip
from pathlib import Path
base = Path(__file__).resolve().parent
text = gzip.decompress((base.parent / 'HP LaserJet 1022.gz').read_bytes()).decode('latin-1')
old = '/Library/Printers/hp/laserjet/hplaserjetzjs.bundle/Contents/MacOS/rasterToHPZJS'
assert text.count(old) == 1
text = text.replace(old, '/Library/Printers/HP1020Duplex/hp1020duplex')
# Repair two mismatched JCL terminators in the upstream HP PPD.
for keyword in ('JamRecovery', 'PrintDensity'):
    text = text.replace('*CloseUI: *' + keyword, '*JCLCloseUI: *' + keyword)
text = text.replace('*NickName: "HP LaserJet 1022, 1.6.1"', '*NickName: "HP LaserJet 1020 Manual Duplex Prototype"')
text += '''
*% Native manual duplex wrapper. Keep hardware duplex disabled.
*cupsManualCopies: True
*OpenGroup: HP1020Options/HP 1020 Printing
*OpenUI *HPManualDuplex/Manual Two-Sided Printing: PickOne
*OrderDependency: 10 AnySetup *HPManualDuplex
*DefaultHPManualDuplex: LongEdge
*HPManualDuplex Off/Off: ""
*HPManualDuplex LongEdge/On - Long Edge: ""
*HPManualDuplex ShortEdge/On - Short Edge: ""
*CloseUI: *HPManualDuplex
*CloseGroup: HP1020Options
'''
# Existing PPD advertises these languages; supply English fallback labels for the new control.
import re
languages = re.search(r'\*cupsLanguages: "([^"]+)"', text).group(1).split()
for language in languages:
    if language == 'en':
        continue
    text += f'*{language}.Translation HPManualDuplex/Manual Two-Sided Printing: ""\n'
    for choice, label in [('Off', 'Off'), ('LongEdge', 'On - Long Edge'), ('ShortEdge', 'On - Short Edge')]:
        text += f'*{language}.HPManualDuplex {choice}/{label}: ""\n'
(base / 'build' / 'HP1020-ManualDuplex.ppd').write_bytes(text.encode('latin-1'))
