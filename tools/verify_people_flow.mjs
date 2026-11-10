// Local integration check for "my route" and "guild" over the real HTTP API and the local D1 file.
// Creates three throw-away accounts (guild master, member, outsider), exercises consent and visibility, then removes
// everything it created. Never targets a hosted site and never reads player files.
//   node tools/verify_people_flow.mjs [path-to-local-d1.sqlite]
import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { readdirSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import path from 'node:path';

const base = 'http://127.0.0.1:5173';
const d1Dir = path.join('platform', '.wrangler', 'state', 'v3', 'd1', 'miniflare-D1DatabaseObject');
const file = process.argv[2] ?? path.join(d1Dir, readdirSync(d1Dir).find(name => name.endsWith('.sqlite') && name !== 'metadata.sqlite'));
const db = new DatabaseSync(file);
const now = Math.floor(Date.now() / 1000);
const run = randomBytes(4).toString('hex');
const people = {};
let passed = 0;
function check(label, condition) { assert(condition, label); passed++; console.log('PASS', label); }

function account(key, name) {
  const token = randomBytes(24).toString('base64url');
  const id = `ptest-${run}-${key}`;
  db.prepare("INSERT INTO et_users(id,discord_id,username,display_name,avatar,created_at,last_login_at) VALUES(?,NULL,?,?,NULL,?,?)").run(id, id, name, now, now);
  db.prepare("INSERT INTO et_sessions(token_hash,user_id,created_at,expires_at) VALUES(?,?,?,?)").run(createHash('sha256').update(token).digest('hex'), id, now, now + 3600);
  return { id, name, cookie: `et_session=${token}`, producerId: `ptest-${run}-${key}`, charId: `Player-${run}-${key}` };
}
async function call(who, method, url, body) {
  const response = await fetch(base + url, { method, headers: { Origin: base, Cookie: who.cookie, ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
  const data = await response.json().catch(() => ({}));
  return { status: response.status, data };
}
const game = { product: 'forever', build: 'integration-test', interface: 16001, region: 'test', realm: 'Test' };
const event = (who, suffix, kind, payload, at = now) => ({ schemaVersion: 1, eventId: `${who.producerId}:${suffix}`, producerId: who.producerId, origin: 'local_observation', kind, observedAt: at, game,
  character: { id: who.charId, name: who.name, realm: 'Test', classId: 8, raceId: 1, level: 30 }, payload, evidence: 'api_snapshot' });
const scopes = ['own_character', 'own_track', 'guild_share'];
async function upload(who, events, withScopes = scopes) {
  const consent = await call(who, 'POST', '/api/consents', { producerId: who.producerId, consentEpoch: 1, since: now - 600, scopes: withScopes });
  assert(consent.status < 300, 'consent: ' + JSON.stringify(consent.data));
  who.grantId = consent.data.grant.id;
  return call(who, 'POST', '/api/uploads', { grantId: who.grantId, export: { schemaVersion: 1, enabled: true, producerId: who.producerId, consentEpoch: 1, since: now - 600, scopes: withScopes, events } });
}
const route = (x0, y0) => ({ mapId: 1429, mapSystem: 'ui_map', startedAt: now - 300, points: [[0, x0, y0], [60, x0 + 0.01, y0], [120, x0 + 0.02, y0 + 0.01]] });

try {
  // zone map 1429 exists in the world data; the three characters are in the same guild on one realm
  for (const [key, name] of [['gm', 'Aria'], ['bob', 'Bran'], ['eve', 'Eve']]) people[key] = account(key, `${name}${run}`);
  const { gm, bob, eve } = people;
  const roster = [{ name: gm.name, rankIndex: 0, level: 30, classId: 8 }, { name: bob.name, rankIndex: 3, level: 25, classId: 3 }];

  check('guild master uploads identity, roster and route', (await upload(gm, [event(gm, 'g', 'guild.snapshot', { guildName: `Dawn${run}`, rankIndex: 0, rankName: 'Master', roster }), event(gm, 't', 'track.path', route(0.4, 0.4))])).data.accepted === 2);
  check('member uploads identity and route', (await upload(bob, [event(bob, 'g', 'guild.snapshot', { guildName: `Dawn${run}`, rankIndex: 3 }), event(bob, 't', 'track.path', route(0.5, 0.5))])).data.accepted === 2);
  check('outsider uploads identity and route', (await upload(eve, [event(eve, 'g', 'guild.snapshot', { guildName: `Dawn${run}`, rankIndex: 1 }), event(eve, 't', 'track.path', route(0.6, 0.6))])).data.accepted === 2);

  const own = await call(bob, 'GET', '/api/track?hours=24');
  check('own route comes back, only mine', own.status === 200 && own.data.paths.length === 1 && own.data.paths[0].points.length === 3 && own.data.characters.length === 1);
  check('anonymous visitor gets no route', (await fetch(base + '/api/track')).status === 401);

  let view = (await call(bob, 'GET', '/api/guild')).data.guilds[0];
  check('member sees the guild and who imported it, but no members before confirming', view.ownerName === gm.name && view.members === null && view.mine[0].eligible === true);
  check('outsider is not in the roster and cannot join', (await call(eve, 'GET', '/api/guild')).data.guilds[0].mine[0].eligible === false);
  const eveJoin = await call(eve, 'POST', `/api/guild/${view.id}`, { profileId: (await call(eve, 'GET', '/api/guild')).data.guilds[0].mine[0].profileId, action: 'join' });
  check('outsider join is refused', eveJoin.status === 409 && eveJoin.data.error.code === 'guild_not_verified');

  const bobProfile = view.mine[0].profileId;
  const gmView = (await call(gm, 'GET', '/api/guild')).data.guilds[0];
  const gmProfile = gmView.mine[0].profileId;
  check('member joins and shares the route', (await call(bob, 'POST', `/api/guild/${view.id}`, { profileId: bobProfile, action: 'join', share: 'trail' })).data.status === 'active');
  let asGm = (await call(gm, 'GET', '/api/guild')).data.guilds[0];
  check('master has not joined yet: sees no members and no positions', asGm.members === null);
  check('master joins', (await call(gm, 'POST', `/api/guild/${view.id}`, { profileId: gmProfile, action: 'join' })).data.status === 'active');
  asGm = (await call(gm, 'GET', '/api/guild')).data.guilds[0];
  const bobRow = asGm.members.find(member => member.profileId === bobProfile);
  check('master sees the member\'s last position', bobRow?.onMap === true && Math.abs(bobRow.position.x - 0.52) < 1e-9 && bobRow.position.mapId === 1429);
  check('master sees the rest of the roster as not on the map only if they have no account', asGm.members.length === 2);
  const trail = await call(gm, 'GET', `/api/guild/${view.id}/trail?profile=${bobProfile}&hours=72`);
  check('master can load the route of a member who shares routes', trail.status === 200 && trail.data.paths.length === 1);
  check('outsider cannot load that route', (await call(eve, 'GET', `/api/guild/${view.id}/trail?profile=${bobProfile}&hours=72`)).status === 403);

  check('member switches to last position only', (await call(bob, 'POST', `/api/guild/${view.id}`, { profileId: bobProfile, action: 'share', share: 'last' })).data.share === 'last');
  check('route is no longer available to the master', (await call(gm, 'GET', `/api/guild/${view.id}/trail?profile=${bobProfile}&hours=72`)).status === 403);
  check('member stops sharing: master sees no position', ((await call(bob, 'POST', `/api/guild/${view.id}`, { profileId: bobProfile, action: 'share', share: 'off' })).status === 200)
    && (await call(gm, 'GET', '/api/guild')).data.guilds[0].members.find(member => member.profileId === bobProfile).position === null);

  check('revoking the consent hides the member\'s route', (await call(bob, 'DELETE', `/api/consents/${bob.grantId}`)).status === 200
    && (await call(bob, 'GET', '/api/track?hours=24')).data.paths.length === 0);

  check('erase deletes only my own route', (await call(gm, 'DELETE', '/api/track')).data.erased === 1 && (await call(eve, 'GET', '/api/track?hours=24')).data.paths.length === 1);
  const lone = people.x = account('x', 'Lone' + run);
  const refused = await upload(lone, [event(lone, 'g', 'guild.snapshot', { guildName: `Dawn${run}`, rankIndex: 1 })], ['guild_share']);
  check('guild sharing without the character scope is refused', refused.status === 403 && refused.data.error.code === 'identity_scope_denied');
} finally {
  for (const who of Object.values(people)) {
    await fetch(base + '/api/me/data', { method: 'DELETE', headers: { Origin: base, Cookie: who.cookie } }).catch(() => {});
    for (const table of ['et_guild_members']) db.prepare(`DELETE FROM ${table} WHERE user_id=?`).run(who.id);
    db.prepare('DELETE FROM atlas_sources WHERE user_id=?').run(who.id);
    db.prepare('DELETE FROM atlas_grants WHERE user_id=?').run(who.id);
    db.prepare('DELETE FROM et_sessions WHERE user_id=?').run(who.id);
    db.prepare('DELETE FROM et_users WHERE id=?').run(who.id);
  }
  db.prepare("DELETE FROM et_guilds WHERE name LIKE ?").run(`Dawn${run}`);
  const left = db.prepare("SELECT (SELECT COUNT(*) FROM et_users WHERE id LIKE ?) users, (SELECT COUNT(*) FROM atlas_observations WHERE user_id LIKE ?) obs, (SELECT COUNT(*) FROM et_guilds WHERE name=?) guilds").get(`ptest-${run}-%`, `ptest-${run}-%`, `Dawn${run}`);
  console.log('cleanup left:', JSON.stringify(left));
  assert.deepEqual({ ...left }, { users: 0, obs: 0, guilds: 0 });
}
console.log(`\n${passed} checks passed`);
