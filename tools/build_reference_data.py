"""Build versioned, offline reference assets from explicit sources, never player data.

Map artwork is read from the installed wowf CASC files using OpenMap's MIT tool.
Metadata is from Wago DB2 build 1.60.1.70291; source provenance is shipped separately.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import base64, csv, hashlib, html, importlib.util, io, json, math, re, shutil, urllib.request, zipfile
import cbor2
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "shared/sources"
ASSETS = ROOT / "shared/assets"
PUBLIC = ROOT / "platform/public/media"
DB = Path(r"D:\World of Warcraft\_forever_\Interface\AddOns\QuestieDB")

def write(folder, name, value):
    folder.mkdir(parents=True, exist_ok=True)
    (folder/name).write_text(json.dumps(value,ensure_ascii=False,separators=(",",":")),encoding="utf8")

def fetch(url, target):
    if not target.exists():
        target.parent.mkdir(parents=True,exist_ok=True)
        request=urllib.request.Request(url,headers={"User-Agent":"Evertally-reference-builder"})
        with urllib.request.urlopen(request,timeout=60) as r: target.write_bytes(r.read())
    return target.read_bytes()

def module(name, file):
    spec=importlib.util.spec_from_file_location(name,file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

def maps():
    world=module("reference_uimap",SOURCE/"tools-uimap.py").World(str(SOURCE))
    casc=module("reference_casc",SOURCE/"tools-casc-casc.py").Casc(r"D:\World of Warcraft","wowf")
    tiles=list(csv.DictReader((SOURCE/"UiMapArtTile.csv").open(encoding="utf8")))
    with zipfile.ZipFile(SOURCE/"OpenMap-v0.8.2-forever.zip") as z:
        reveal=z.read("OpenMap/Data/Forever/Reveal.lua").decode()
    overlays={int(k):re.findall(r'\["([\d:]+)"\]\s*=\s*"([\d, ]+)"',body) for k,body in re.findall(r'^\s*\[(\d+)\]\s*=\s*\{(.*)\},',reveal,re.M)}
    chosen=[m for m in world.uimap if world.art(m) and (m in [947,1414,1415] or any(int(r['UiMapID'])==m for r in world.assign.get(m,[])))]
    catalog=[]; out=ASSETS/"maps";out.mkdir(parents=True,exist_ok=True)
    for mid in sorted(chosen):
        art,width,height,tw,th=world.art(mid)
        rows=[r for r in tiles if int(r["UiMapArtID"])==art and r["LayerIndex"]=="0"]
        if not rows:continue
        name=world.uimap[mid]['Name_lang'];key=re.sub(r'[^a-z0-9]+','-',name.lower()).strip('-') or str(mid)
        if any(x['key']==key for x in catalog):key+=f'-{mid}'
        image=Image.new('RGBA',(width,height))
        try:
            for row in rows:
                tile=Image.open(io.BytesIO(casc.read(int(row['FileDataID'])))).convert('RGBA')
                image.alpha_composite(tile,(int(row['ColIndex'])*tw,int(row['RowIndex'])*th))
            for geometry,fids in overlays.get(art,[]):
                ow,oh,x,y=map(int,geometry.split(':'));cols=math.ceil(ow/256)
                for index,fid in enumerate(re.findall(r'\d+',fids)):
                    tile=Image.open(io.BytesIO(casc.read(int(fid)))).convert('RGBA')
                    sx,sy=(index%cols)*256,(index//cols)*256
                    tile=tile.crop((0,0,min(256,ow-sx),min(256,oh-sy)))
                    image.alpha_composite(tile,(x+sx,y+sy))
        except (KeyError,ValueError,OSError) as e:
            print('Unavailable map skipped',mid,type(e).__name__);continue
        image.convert('RGB').save(out/(key+'.jpg'),quality=88,optimize=True)
        entry={'key':key,'nameEn':name,'nameCs':name,'image':'/media/maps/'+key+'.jpg','width':width,'height':height,'uiMapIds':[mid],'sourceLabel':'Blizzard wowf 1.60.1.70862; DB2 1.60.1.70291'}
        catalog.append(entry)
    byid={mid:m for m in catalog for mid in m['uiMapIds']}
    for m in catalog:
        mid=m['uiMapIds'][0];parent=world.parent(mid)
        if parent in byid and (r:=world.rect(mid)) and (pr:=world.rect(parent)):
            x=(r[0]-pr[0])/(pr[1]-pr[0]);y=(r[2]-pr[2])/(pr[3]-pr[2]);ww=(r[1]-r[0])/(pr[1]-pr[0]);hh=(r[3]-r[2])/(pr[3]-pr[2])
            if min(x,y)>=0 and x+ww<=1.001 and y+hh<=1.001:m['bounds']={'parentKey':byid[parent]['key'],'x':x,'y':y,'width':ww,'height':hh}
    write(out,'manifest.json',{'schemaVersion':1,'maps':catalog})
    print('Built map assets',len(catalog),flush=True)

def clean(value):
    if isinstance(value,bytes):return value.decode('utf8','replace')
    if isinstance(value,list):return [clean(v) for v in value]
    if isinstance(value,dict):return {clean(k):clean(v) for k,v in value.items()}
    return value

def catalogs():
    meta=dict(re.findall(r'^## (X-(?:Npc|Quest|Item)-[^:]+): (.*)$',(DB/'QuestieDB_Forever.toc').read_text(encoding='utf8'),re.M))
    def get(key):
        raw=meta.get(key)
        if raw and raw.startswith('~'):raw=''.join(meta[key+'-'+str(i)] for i in range(1,int(raw.strip('~'))+1))
        return clean(cbor2.loads(base64.b64decode(raw))) if raw else None
    amap={int(a):int(b) for a,b in re.findall(r'\[(\d+)\]\s*=\s*(\d+)',(DB/'support/Forever/Zones/areaIdToUiMapId.lua').read_text(encoding='utf8'))}
    for r in csv.DictReader((SOURCE/'UiMapAssignment.csv').open()):
        if int(r['AreaID'])>0:amap.setdefault(int(r['AreaID']),int(r['UiMapID']))
    npc=[];quests=[];world=[]
    def array(value):return value if isinstance(value,list) else []
    for key in meta:
        match=re.fullmatch(r'X-(Npc|Quest)-(\d+)-S',key)
        if not match:continue
        kind,sid=match.groups();id=int(sid);row=get(key)
        if not isinstance(row,dict):continue
        name=row.get(1) or f'{kind} #{id}'
        if kind=='Quest':
            starts=get(f'X-Quest-{id}-2');ends=get(f'X-Quest-{id}-3')
            entry={'id':id,'name':name,'level':row.get(5),'requiredLevel':row.get(4),'starts':array(starts[0]) if isinstance(starts,list) and starts else [],'ends':array(ends[0]) if isinstance(ends,list) and ends else [],'objectives':array(get(f'X-Quest-{id}-8')),'zoneId':amap.get(row.get(17)),'sourceLabel':'QuestieDB 1.0.13 Forever reference (base rows; corrections may differ)'}
            quests.append(entry)
        else:
            spawns=get(f'X-Npc-{id}-7') or {};locations=[]
            pairs=spawns.items() if isinstance(spawns,dict) else enumerate(spawns,1)
            for area,coords in pairs:
                mid=amap.get(area)
                if not mid:continue
                for pair in array(coords)[:100]:
                    if isinstance(pair,list) and len(pair)>=2 and all(isinstance(v,(float,int)) and 0<=v<=100 for v in pair[:2]):locations.append({'mapId':mid,'mapSystem':'ui_map','x':pair[0]/100,'y':pair[1]/100,'positionMethod':'npc_database'})
            entry={'id':id,'name':name,'levelMin':row.get(4),'levelMax':row.get(5),'startsQuests':array(get(f'X-Npc-{id}-10')),'endsQuests':array(get(f'X-Npc-{id}-11')),'locations':locations,'sourceLabel':'QuestieDB 1.0.13 Forever reference (base rows; corrections may differ)','isVendor':bool(int(row.get(15,0))&128)}
            npc.append(entry)
            if locations:world.append({'id':str(id),'kind':'npc','name':name,'count':0,'origin':'catalog','sourceLabel':entry['sourceLabel'],'isVendor':entry['isVendor'],'locations':locations,'payload':{'level':row.get(4)}})
    raw=json.loads(fetch('https://raw.githubusercontent.com/Napalmsteak/WoW-Classic-Item-Caches/main/Forever%20Cache.json',SOURCE/'forever-items.json'))
    sources=json.loads((SOURCE/'itemSources.json').read_text())
    if isinstance(sources,dict):sources=list(sources.values())
    sources={s['key']:s for s in sources}
    items=[]
    for item in raw:
        tooltip=item.get('tooltipHtml','');icon=item.get('iconName','inv_misc_questionmark')
        text=html.unescape(re.sub('<[^>]+>',' ',re.sub(r'<br\s*/?>','\n',tooltip)))
        quality=re.search(r'class="q([0-7])"',tooltip);ilvl=re.search(r'Item Level\s*(\d+)',text);req=re.search(r'Requires Level\s*(\d+)',text)
        items.append({'id':item['itemId'],'name':item['name'],'icon':'/media/identity/items/'+str(item['itemId'])+'.jpg','iconName':icon,'quality':int(quality[1]) if quality else None,'itemLevel':int(ilvl[1]) if ilvl else None,'requiredLevel':int(req[1]) if req else None,'description':re.sub(r'[ \t]+',' ',text).strip(),'sources':[{'name':sources[k].get('name',k),'type':sources[k].get('type')} for k in item.get('sourceKeys',[]) if k in sources],'bosses':item.get('bossNames',[]),'sourceLabel':'Forever item cache, snapshot 2026-11-07','sourceUrl':item.get('itemUrl')})
    items.sort(key=lambda item: ('[TMP]' in item['name'] or bool(re.match(r'^\d+ (?:Green|Blue|Epic) ',item['name'])),item['name'].lower()))
    instances=[]
    for key,source in sources.items():
        if source.get('expansion')!='Forever' or source.get('type') not in ['Dungeon','Raid']:continue
        loot=[i['itemId'] for i in raw if key in i.get('sourceKeys',[])];bosses=sorted(set(b for i in raw if key in i.get('sourceKeys',[]) for b in i.get('bossNames',[])))
        instances.append({'id':key,'name':source['name'],'type':source['type'].lower(),'bosses':bosses,'loot':loot,'sourceLabel':'Forever item cache source catalogue','description':'Reference loot sources; recorded visits and timings are shown separately.'})
    guides=[{'id':'first-run','title':'První výprava / First run','category':'Evertally','sourceLabel':'Evertally instructions','steps':[{'title':'Instalace / Installation','body':'Nainstaluj Evertally, v nastavení vyber složku WoW Forever a zapni spuštění s hrou. Install Evertally, select the WoW Forever folder and enable Start with WoW.'},{'title':'Záznam / Recording','body':'Addon sleduje vlastní vstupy do instancí, boss události a konec běhu. /reload přeruší měření a nesmí vytvářet rychlostní rekord. The addon records instance entries and boss events; reload breaks timing.'},{'title':'Web / Sync','body':'Web je dobrovolný: povol export v addonu, přihlas se a potvrď párovací kód i rozsah. Přesné pozice hráčů se nesdílejí. Web sync requires explicit addon consent and device pairing; exact player positions are never shared.'}]}, {'id':'map-reference','title':'Mapa a zdroje / Map sources','category':'Map','sourceLabel':'Evertally instructions','steps':[{'title':'Pozorování a databáze','body':'Databázové výskyty NPC jsou referenční data, nejsou živé pozice ani důkaz drop rate. NPC database spawns are reference data, not live positions or measured drop rates.'},{'title':'Navštívené oblasti','body':'U postav jsou jen navštívené oblasti. Komunitní aktivita shrnuje různé přispívající účty za den a skrývá zóny s méně než třemi účty. Characters expose visited zones only; aggregate activity hides zones below three contributors.'}]}]
    out=ASSETS/'catalog'
    for name,entries in [('npcs',npc),('quests',quests),('items',items),('instances',instances),('guides',guides)]:write(out,name+'.json',{'schemaVersion':1,'entries':entries});print(name,len(entries),flush=True)
    write(out,'world.json',{'schemaVersion':1,'entities':world})
    return items

def icons(items):
    classes={1:'Warrior',2:'Paladin',3:'Hunter',4:'Rogue',5:'Priest',7:'Shaman',8:'Mage',9:'Warlock',11:'Druid'}
    races={1:'human',2:'orc',3:'dwarf',4:'nightelf',5:'undead',6:'tauren',7:'gnome',8:'troll',9:'goblin'}
    jobs=[]
    for kind,values,pattern in [('classes',classes,'GarrMission_ClassIcon-{}.png'),('races',races,'raceicon-{}-male.png')]:
        for id,name in values.items():jobs.append(('https://raw.githubusercontent.com/Hoizame/WoW_ClassicUIResources/master/UiAtlasTextureFiles/'+pattern.format(name),ASSETS/'identity'/kind/(str(id)+'.png')))
    def one(job):
        try:fetch(*job);return True
        except Exception as error:print('Missing optional identity asset',job[1].name,type(error).__name__);return False
    with ThreadPoolExecutor(max_workers=8) as pool:list(pool.map(one,jobs))
    archive=SOURCE/'item-caches.zip';fetch('https://codeload.github.com/Napalmsteak/WoW-Classic-Item-Caches/zip/refs/heads/main',archive)
    out=ASSETS/'identity/items';out.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        index={Path(n).name:n for n in z.namelist() if '/icons/' in n and n.endswith('.jpg')}
        for item in items:
            name=item['iconName']+'.jpg'
            if name in index:(out/(str(item['id'])+'.jpg')).write_bytes(z.read(index[name]))
    print('Item icons',len(list(out.glob('*.jpg'))),flush=True)

if __name__=='__main__':
    maps();items=catalogs();icons(items)
    for folder in ['maps','identity']:shutil.copytree(ASSETS/folder,PUBLIC/folder,dirs_exist_ok=True)
    licenses=ASSETS/'licenses';licenses.mkdir(parents=True,exist_ok=True)
    for source,name in [(SOURCE/'openmap-LICENSE.txt','OpenMap-MIT.txt'),(DB/'LICENSE.md','QuestieDB-LICENSE.md'),(DB/'gpl-3.0.md','GPL-3.0.md')]:shutil.copy2(source,licenses/name)
    notice='Map and icon artwork: Blizzard Entertainment. OpenMap tools/data: MIT, OpenMap contributors. Reference NPC/quest base data: installed QuestieDB 1.0.13 Forever, with source licence included; runtime corrections are not applied. Forever item facts/icons: https://github.com/Napalmsteak/WoW-Classic-Item-Caches . Maps use installed wowf build 1.60.1.70862 and Wago map metadata 1.60.1.70291. Reference data is separate from player observations; never player tracking. Web map and database (not yet published): zone placement from the UiMap tables of the game (wago.tools build 1.60.1.70862); OpenMap data tables (MIT, openmap-world/openmap): zone levels, instance entrances, boats and zeppelins, floor lists; Shortest Path Forever (GPL-3.0, cjber): flight nodes/paths with measured flight seconds (InFlight, MIT), walking yards between fixed places, transport timetables, portals; AtlasLoot Forever (GPL-2.0): raid loot tables and measured drop rates (facts only); SkillUp Forever (GPL-3.0): profession recipes and skill thresholds (facts only); LibForeverData forever-db (CC BY 4.0 for quest steps/notes; EG Link by Efficient Games CC BY 4.0, CMaNGOS classic-db, pfQuest MIT, ForeverTDB, QuestieDB): quest tips; DungeonJournal addon by Exehn: facts only (names, IDs, levels, coordinates); its Home artwork (Blizzard art) is used as dungeon banners. Dungeon floor maps and loading screens: Blizzard Entertainment, read from the installed game client. See THIRD_PARTY.md.'
    (ASSETS/'ASSET_SOURCES.txt').write_text(notice,encoding='utf8');shutil.copy2(ASSETS/'ASSET_SOURCES.txt',PUBLIC/'ASSET_SOURCES.txt')
    print('Shared offline resources and web copies complete.')
