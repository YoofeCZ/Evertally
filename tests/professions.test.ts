import test from "node:test";
import assert from "node:assert/strict";
import {DatabaseSync} from "node:sqlite";
import {buildProfessionData,PROFESSION_ROWS_SQL} from "../lib/professions";
const row=(id:string,kind:string,payload:unknown,at:number,character:unknown={id:"own",name:"Hero"})=>({id,kind,producer_id:"source",payload:JSON.stringify(payload),character_data:JSON.stringify(character),observed_at:at});
test("Professions use newest snapshot per character, preserve missing skill and exact observed craft quantities",()=>{
 const data=buildProfessionData([
 row("a","profession.snapshot",{professionId:171,skill:1,recipes:[]},1),
 row("b","profession.snapshot",{professionId:171,skill:75,recipes:[{recipeId:100,learned:true}]},2),
 row("c","craft.result",{recipeId:100,quantity:3},3),
 row("d","profession.snapshot",{professionId:164,recipes:[]},4),
 row("e","cooldown.snapshot",{recipeId:100,readyAt:1000},5),row("f","cooldown.snapshot",{recipeId:100,readyAt:2000},6),
 ],6,10);
 const c=data.characters[0];assert.equal(c.professions.find(p=>p.professionId===171)?.skill,75);
 assert.equal(c.professions.find(p=>p.professionId===164)?.skill,null);assert.equal(c.crafts[0].quantity,3);
 assert.equal(c.cooldowns.length,1);assert.equal(c.cooldowns[0].readyAt,2000);assert.equal(data.truncated,false);
});
test("Hidden profession identity remains null and malformed observations do not become zero skills",()=>{
 const data=buildProfessionData([row("a","profession.snapshot",{professionId:171,recipes:[]},1,null),row("b","profession.snapshot",{skill:999},2)],20,10);
 assert.equal(data.characters.length,1);assert.equal(data.characters[0].character,null);assert.equal(data.characters[0].professions[0].skill,null);assert.equal(data.truncated,true);
});
test("Profession SQL enforces owner, scope and a bounded cumulative byte budget",()=>{
 const db=new DatabaseSync(":memory:");db.exec("CREATE TABLE atlas_observations(id TEXT,user_id TEXT,scope TEXT,producer_id TEXT,kind TEXT,payload TEXT,character_data TEXT,observed_at INTEGER)");
 const insert=db.prepare("INSERT INTO atlas_observations VALUES(?,?,?,?,?,?,?,?)");
 insert.run("own","u","own_professions","p","profession.snapshot","{}",null,1);
 insert.run("foreign","other","own_professions","p","profession.snapshot","{}",null,2);
 insert.run("wrong-scope","u","world_facts","p","profession.snapshot","{}",null,3);
 assert.equal(db.prepare(PROFESSION_ROWS_SQL).all("u").length,1);
 insert.run("huge","u","own_professions","p","profession.snapshot","x".repeat(2097153),null,4);
 assert.equal(db.prepare(PROFESSION_ROWS_SQL).all("u").length,0);db.close();
});
