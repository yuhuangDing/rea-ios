"""Slice finished transparent 4-column art sheets. Usage: pack_art.py path/to/named/sheets."""
from pathlib import Path
import argparse
from PIL import Image

SETS = {
    'allied': 'GACNST GAPOWR GAREFN GAPILE GAWEAP AMRADR GATECH GAYARD GAPILL ATESLA GADEPT GAWEAT',
    'soviet': 'NACNST NAPOWR NAREFN NAHAND NAWEAP NARADR NATECH NAYARD NALASR TESLA NADEPT NAMISL',
    'armorA': 'AMCV CMIN MTNK FV SREF TNKD ORCA BEAG DEST AEGIS GTGCAN JUMPJET',
    'armorS': 'SMCV HARV HTNK HTK APOC TTNK DTRUCK ZEP SUB DRED SHK DESO',
    'squad': 'E1 E2 ENGINEER SENGINEER ADOG DOG SNIPE TERROR',
    'scenery': 'pine pines olive birch rock gold gem snowpine',
}
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sheets', type=Path)
    args = parser.parse_args()
    output = Path(__file__).resolve().parents[1] / 'IronFront/Art/Sprites'
    output.mkdir(exist_ok=True)
    for name in [*SETS, 'armorARear', 'armorSRear']:
        rear = name.endswith('Rear')
        ids = SETS[name.removesuffix('Rear')].split()
        atlas = Image.open(args.sheets/(name+'.png')).convert('RGBA')
        w,h = atlas.size
        rows = len(ids)//4
        for i, key in enumerate(ids):
            if rear and key == 'GTGCAN':
                continue
            x,y=i%4,i//4
            cell=atlas.crop((round(x*w/4),round(y*h/rows),round((x+1)*w/4),round((y+1)*h/rows)))
            bbox=cell.getchannel('A').point(lambda a: 255 if a>45 else 0).getbbox()
            if not bbox:
                raise ValueError(key)
            cell=cell.crop(bbox)
            cell.save(output/(key+('-rear' if rear else '')+'.png'),optimize=True)
if __name__ == '__main__':
    main()
