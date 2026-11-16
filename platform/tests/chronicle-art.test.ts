import test from "node:test";
import assert from "node:assert/strict";
import { loadChronicleArt, sameArtName } from "../lib/chronicle-art";
const response = (body:string) => (async()=>new Response(body)) as typeof fetch;
test("spell art uses the actual spell ID and only a safe icon filename",async()=>{
  let requested="";
  const art=await loadChronicleArt({kind:"spell",id:78},(async url=>{requested=String(url);return Response.json({name:"Heroic Strike",icon:"Ability_Rogue_Ambush"});}) as typeof fetch);
  assert.equal(requested,"https://nether.wowhead.com/classic/tooltip/spell/78");
  assert.equal(art.image,"https://wow.zamimg.com/images/wow/icons/large/ability_rogue_ambush.jpg");
  assert.deepEqual(await loadChronicleArt({kind:"spell",id:78},response('{"name":"Spell","icon":"../../bad"}')),{});
});
test("NPC art resolves an old unique name from the bundled model facts without an upstream page request",async()=>{
  const art=await loadChronicleArt({kind:"npc",name:"Plainstrider"},(async()=>{throw new Error("Must not fetch");}) as typeof fetch);
  assert.equal(art.image,"https://wow.zamimg.com/modelviewer/classic/webthumbs/npc/195/1219.webp");
});
test("unresolved/player names never cause an upstream search and incorrect names cannot substitute custom Forever art",async()=>{
  const art=await loadChronicleArt({kind:"npc",name:"A private player name"},(async()=>{throw new Error("Must not fetch");}) as typeof fetch);
  assert.deepEqual(art,{});
  for(const name of ["constructor","__proto__"])assert.deepEqual(await loadChronicleArt({kind:"npc",name},(async()=>{throw new Error("Must not fetch");}) as typeof fetch),{});
  assert.equal(sameArtName("Custom Forever spell","Another spell"),false);
  assert.equal(sameArtName(" Heroic Strike ","heroic strike"),true);
});
test("an observed display ID can supply a model without any name lookup",async()=>{
  const art=await loadChronicleArt({kind:"npc",displayId:1219},(async()=>{throw new Error("Must not fetch");}) as typeof fetch);
  assert.ok(art.image?.endsWith('/195/1219.webp'));
});
