"""Reproduce isolated GPL-3.0-or-later SPF road/collision routing sources.

Only namespace references change. Run against an installed Shortest Path Forever
copy; never writes into that addon. The bundled data retains collision edges,
height/floors and directed steep/drop steps, unlike the obsolete EVWM mask.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parents[1]
TARGET=ROOT/'addon/Evertally_Map/Roads'
DEFAULT=Path(r"D:\World of Warcraft\_forever_\Interface\AddOns\ShortestPathForever")


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,default=DEFAULT)
    args=parser.parse_args()
    source=args.source.resolve()
    TARGET.mkdir(parents=True,exist_ok=True)
    toc=(source/'ShortestPathForever.toc').read_text(encoding='utf-8-sig')
    version=re.search(r'^## Version: (.+)$',toc,re.M).group(1)
    if version!='v1.35.0':
        raise ValueError(f'Review the decoder/adapter before replacing pinned SPF v1.35.0 with {version}')
    nav=re.findall(r'<Script file="([^"]+)"', (source/'Nav/Nav.xml').read_text())
    files=['Data/RoadCells.lua','Data/RoadEdges.lua']+[f'Nav/{n}' for n in nav]+['Routing/PathGrid.lua','Routing/Path.lua','Routing/PathJobs.lua']
    records=[]
    for name in files:
        original=(source/name).read_bytes()
        text=original.decode('utf-8-sig').replace('\r\n','\n')
        # Every copied file receives the same private namespace. No third-party
        # active journey, callbacks, settings or decoded caches are shared.
        text=text.replace('local ns = select(2, ...)', 'local ns = select(2, ...)._roadEngine')
        text=text.replace('local _, ns = ...', 'local _, addon = ...\nlocal ns = addon._roadEngine')
        if name.startswith('Nav/'):
            text='local ns = select(2, ...)._roadEngine\n'+text
        text=text.replace('ShortestPathForeverPathData','ns.NavData')
        output=TARGET/name
        output.parent.mkdir(parents=True,exist_ok=True)
        output.write_text(text,encoding='utf-8',newline='\n')
        records.append({'source':name,'sha256':hashlib.sha256(original).hexdigest(),'bundled':'Roads/'+name,'bundledSha256':hashlib.sha256(output.read_bytes()).hexdigest()})
    (TARGET/'LICENSE.txt').write_bytes((source/'LICENSE').read_bytes())
    (TARGET/'NOTICE.txt').write_text(f"Shortest Path Forever {version}\nCopyright: cjber and contributors (see original source headers).\nSource: https://github.com/cjber/shortest-path-forever\nLicense: GPL-3.0-or-later; complete license in LICENSE.txt.\n\nFiles under Data/, Nav/ and Routing/ are copied with only namespace substitutions.\nNav data retains the original generator/source hashes and credits in each header.\nReproduce with tools/vendor_roadpath.py against the source version listed in SOURCE-MANIFEST.txt.\nEvertally's Namespace.lua and Adapter.lua provide independent lifecycle and scheduling.\nNo source addon files or player data are changed.\n",encoding='utf-8',newline='\n')
    manifest=json.dumps({'source':'https://github.com/cjber/shortest-path-forever','version':version,'license':'GPL-3.0-or-later','files':records},indent=2)+'\n'
    (TARGET/'manifest.json').write_text(manifest,encoding='utf-8',newline='\n')
    # Existing release tooling includes .txt notices; ship source fingerprints
    # with the binary distribution even when optional JSON tooling is omitted.
    (TARGET/'SOURCE-MANIFEST.txt').write_text(manifest,encoding='utf-8',newline='\n')
    (TARGET/'files.txt').write_text('Roads/Namespace.lua\n'+'\n'.join(r['bundled'] for r in records)+'\nRoads/Adapter.lua\n',encoding='utf-8',newline='\n')
    print(f"Vendored {len(records)} isolated solver/data files from {version}")


if __name__=='__main__': main()
