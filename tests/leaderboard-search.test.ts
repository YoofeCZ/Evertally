import test from "node:test";
import assert from "node:assert/strict";
import { publicRankingObservations, rankObservedRuns, rankPublicLevels } from "../lib/run-rankings";
import type { Run } from "../components/evertally/types";
import { fixture } from "./sqlite-db";

test("level ranking requires public profile and valid own_character consent, excludes unknown levels", async () => {
  const f=fixture([["good","Žofie"],["private","Private"],["revoked","Revoked"],["scope","NoScope"],["unknown","Unknown"],["tie","Tie"]]);
  f.sql.exec(`UPDATE atlas_profiles SET public=1;
    UPDATE atlas_profiles SET public=0 WHERE user_id='private';
    UPDATE atlas_profiles SET level=NULL WHERE user_id='unknown';
    UPDATE atlas_grants SET revoked_at=123 WHERE user_id='revoked';
    UPDATE atlas_grants SET scopes='["own_track"]' WHERE user_id='scope';`);
  for (const user of ["good","private","revoked","scope","unknown","tie"]) f.addTrack(user,1000,1429,.5,.5,`grant-${user}`);
  const all=await rankPublicLevels(f.db,new URLSearchParams());
  assert.deepEqual(all.entries.map(e=>e.character.id),["p-good","p-tie"]);
  assert.deepEqual(all.entries.map(e=>e.rank),[1,2]);
  assert.equal((await rankPublicLevels(f.db,new URLSearchParams({q:"ŽOFIE-test"}))).entries[0].character.id,"p-good");
  assert.equal((await rankPublicLevels(f.db,new URLSearchParams({classId:"1"}))).total,0);
  f.sql.prepare("UPDATE atlas_grants SET scopes=? WHERE user_id='good'").run(JSON.stringify(["own_track"]));
  assert.deepEqual((await rankPublicLevels(f.db,new URLSearchParams())).entries.map(e=>e.character.id),["p-tie"]);
});

test("public observations scan beyond 5000 without exposing revoked or private rows", async () => {
  const f=fixture([["good","Hero"],["private","Private"],["revoked","Revoked"]]);
  f.sql.exec(`UPDATE atlas_profiles SET public=1 WHERE user_id!='private';
    UPDATE atlas_grants SET scopes='["own_runs","own_character"]';
    UPDATE atlas_grants SET revoked_at=123 WHERE user_id='revoked';`);
  const insert=f.sql.prepare(`INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,'run.finished','own_runs',?,?,?, '{}','api_event')`);
  f.sql.exec("BEGIN");
  for (let i=0;i<5005;i++) insert.run(`o${i}`,"good","src-good",`e${i}`,"grant-good",i,"p-good",JSON.stringify({runId:`r${i}`}));
  insert.run("private","private","src-private","private","grant-private",9000,"p-private","{}");
  insert.run("revoked","revoked","src-revoked","revoked","grant-revoked",9001,"p-revoked","{}");
  f.sql.exec("COMMIT");
  const rows=await publicRankingObservations(f.db);
  assert.equal(rows.length,5005);
  assert.equal(rows.at(-1)?.id,"o0");
  assert.equal(rows.some(r=>r.id==="private"||r.id==="revoked"),false);
});

test("ranking filters before pagination and retains overall rank while searching name or realm", () => {
  const runs:Run[]=Array.from({length:90},(_,i)=>({id:`r${i}`,name:"Deadmines",instanceId:36,instanceType:"party",status:"completed",completion:"last_boss",evidence:"api_event",character:{id:`p${String(i).padStart(3,"0")}`,name:i===70?"Žofie":"Hero",realm:i===70?"Dark Realm":"Test",classId:11,raceId:4}}));
  const first=rankObservedRuns(runs,new URLSearchParams({metric:"count",classId:"11",instanceType:"party"}));
  const second=rankObservedRuns(runs,new URLSearchParams({metric:"count",classId:"11",instanceType:"party",page:"1"}));
  assert.equal(first.total,90);assert.equal(first.entries.length,40);assert.equal(second.entries[0].rank,41);
  const found=rankObservedRuns(runs,new URLSearchParams({metric:"count",classId:"11",instanceType:"party",q:"ŽOFIE-dark realm"}));
  assert.equal(found.total,1);assert.equal(found.entries[0].rank,71);
  assert.equal(rankObservedRuns(runs,new URLSearchParams({q:"Dark Realm",classId:"1"})).total,0);
});

test("search reaches an older result after 5000 and ranks it before paging", () => {
  const runs:Run[]=Array.from({length:5051},(_,i)=>({id:`r${i}`,name:"Deadmines",instanceId:36,instanceType:"party",status:"completed",completion:"last_boss",evidence:"api_event",character:{id:`p${String(i).padStart(5,"0")}`,name:i===5049?"Dávný":"Hero",realm:"Test",classId:11,raceId:4}}));
  const result=rankObservedRuns(runs,new URLSearchParams({q:"DÁVNÝ-test",classId:"11",instanceType:"party"}));
  assert.equal(result.total,1);
  assert.equal(result.entries[0].rank,5050);
  assert.equal(rankObservedRuns(runs,new URLSearchParams({page:"125",classId:"11"})).entries[0].rank,5001);
});
