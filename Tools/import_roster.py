"""Refresh the small set of factual L3 fields used by the simulation; takes a local units_data.json."""
import argparse
import json
from pathlib import Path

# Unit ID / original CNCNZ cameo filename. Construction yards inherit their deployed MCV's values.
CAMEOS = dict(pair.split(':') for pair in """
GACNST:cnsticon_proper NACNST:cnsticon_proper GAPOWR:powricon NAPOWR:npwricon
GAREFN:reficon NAREFN:nreficon GAPILE:brrkicon NAHAND:handicon GAWEAP:gwepicon NAWEAP:nwepicon
AMRADR:heliicon NARADR:nradicon GATECH:techicon NATECH:ntchicon GAPILL:pillicon NALASR:plticon
ATESLA:prisicon TESLA:tslaicon GTGCAN:gcanicon GAYARD:ayaricon NAYARD:yardicon
GAWEAT:wethicon NAMISL:msslicon GADEPT:fixicon NADEPT:rfixicon
AMCV:mcvicon SMCV:smcvicon CMIN:ahrvicon HARV:harvicon
E1:giicon E2:e2icon ENGINEER:engnicon SENGINEER:engnicon ADOG:adogicon DOG:dogicon
JUMPJET:jjeticon SHK:shkicon SNIPE:snipicon DESO:desoicon TERROR:trsticon
MTNK:gtnkicon HTNK:htnkicon FV:fvicon HTK:htkicon SREF:sreficon APOC:mtnkicon
TNKD:tnkdicon TTNK:ttnkicon DTRUCK:trkaicon ORCA:falcicon BEAG:beagicon ZEP:zepicon
DEST:desticon AEGIS:agisicon SUB:subicon DRED:dredicon
""".split())
DISPLAY_NAMES = {
    'GACNST': '盟军建造厂', 'NACNST': '苏军建造厂', 'AMRADR': '空指部', 'NARADR': '雷达站',
    'FV': '多功能步兵车', 'TNKD': '坦克杀手', 'TERROR': '古巴爆破手',
    'GADEPT': '盟军维修厂', 'NADEPT': '苏军维修厂', 'GAYARD': '盟军造船厂',
    'NAYARD': '苏军造船厂', 'GTGCAN': '法国巨炮',
}
ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://cncnz.com/wp-content/uploads/2018/04/ra2_'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('json_file', type=Path)
    parser.add_argument('--curl-config', type=Path, help='Also write a curl download manifest for original cameos.')
    args = parser.parse_args()
    archive = json.loads(args.json_file.read_text())
    records = {}
    for side in archive['sides'].values():
        for country in side['countries'].values():
            for family in country['categories'].values():
                for item in family:
                    records.setdefault(item['id'], item)
    rows = {}
    downloads = []
    for key, cameo in CAMEOS.items():
        original = {'GACNST': 'AMCV', 'NACNST': 'SMCV'}.get(key, key)
        record = records[original]
        rows[key] = {
            'name': DISPLAY_NAMES.get(key, record['name']), 'sourceId': original,
            'sourceName': record['name'], 'cost': int(record['cost']), 'hp': int(record['strength']),
            'power': int(record.get('power', 0)), 'sight': int(record['sight']), 'speed': int(record['speed']),
            'armor': record['armor'], 'sourcePrerequisite': record['prerequisite'], 'cameo': cameo,
        }
        downloads.extend([f'url = "{BASE}{cameo}.png"', f'output = "{ROOT}/IronFront/Art/Cameos/{cameo}.png"'])
    out = ROOT / 'Sources/FrontCore/Resources/roster.json'
    out.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
    if args.curl_config:
        (ROOT / 'IronFront/Art/Cameos').mkdir(parents=True, exist_ok=True)
        args.curl_config.write_text('\n'.join(dict.fromkeys(downloads)) + '\n')

if __name__ == '__main__':
    main()
