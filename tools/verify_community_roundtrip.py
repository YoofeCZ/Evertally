"""Replay a server snapshot through the actual Lua addon, without game access."""
import importlib.util,json,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('evertally_replay',root/'tests/lua/test_addon.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
lua,addon=module.runtime()
text=Path(sys.argv[1]).read_text(encoding='utf-8')
data=json.loads(text);lua.globals().NOW=data['generatedAt']
addon.SetWeb(True)
before=addon.Encode(addon.ExportStore())
ok,count=addon.ImportCommunity(text)
assert ok and count==len(data['entities'])
addon.Initialize()
snapshot,stale=addon.GetCommunity()
assert not stale and len(snapshot.entities)==count
assert addon.Encode(addon.ExportStore())==before and len(addon.db.events)==0
assert 'evertally-community' not in addon.Encode(addon.MakeSummary())
print(json.dumps({'imported':count,'survivesReload':True,'ownEventsAdded':0,'peerRelay':False}))
