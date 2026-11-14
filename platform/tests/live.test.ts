import test from "node:test";
import assert from "node:assert/strict";
import {DatabaseSync} from "node:sqlite";
import {livePositions} from "../lib/live-query";
import type {Db} from "../lib/people";

test("Live positions require current device and consent scopes and expire without updates",async()=>{
 const sql=new DatabaseSync(":memory:");
 sql.exec(`CREATE TABLE atlas_grants(id TEXT,user_id TEXT,scopes TEXT,revoked_at INTEGER);CREATE TABLE et_devices(id TEXT,user_id TEXT,scopes TEXT,revoked_at INTEGER);CREATE TABLE et_live_positions(profile_id TEXT,user_id TEXT,grant_id TEXT,device_id TEXT,observed_at INTEGER,expires_at INTEGER,map_id INTEGER,x REAL,y REAL);`);
 const db={prepare(query:string){let args:unknown[]=[];const stmt={bind(...values:unknown[]){args=values;return stmt;},async all(){return {results:sql.prepare(query).all(...args as (string|number|null)[])};}};return stmt;}} as unknown as Db;
 const scopes=JSON.stringify(["own_character","own_track","guild_share"]);
 sql.prepare('INSERT INTO atlas_grants VALUES(?,?,?,NULL)').run('grant','owner',scopes);
 sql.prepare('INSERT INTO et_devices VALUES(?,?,?,NULL)').run('device','owner',scopes);
 sql.prepare('INSERT INTO et_live_positions VALUES(?,?,?,?,?,?,?,?,?)').run('profile','owner','grant','device',100,130,1429,.42,.65);
 assert.equal((await livePositions(db,['profile'],['own_track'],105)).get('profile')?.x,.42);
 assert.equal((await livePositions(db,['someone-else'],['own_track'],105)).size,0);
 assert.equal((await livePositions(db,['profile'],['own_track'],131)).size,0);
 sql.exec("UPDATE et_devices SET revoked_at=106");
 assert.equal((await livePositions(db,['profile'],['own_track'],107)).size,0);
 sql.exec("UPDATE et_devices SET revoked_at=NULL;UPDATE atlas_grants SET revoked_at=108");
 assert.equal((await livePositions(db,['profile'],['own_track'],109)).size,0);
 sql.exec("UPDATE atlas_grants SET revoked_at=NULL,scopes='[\"own_track\",\"own_character\"]'");
 assert.equal((await livePositions(db,['profile'],['own_track','guild_share'],109)).size,0);
 sql.close();
});
