// Local integration check for groups and meets over the real HTTP API and the local D1 file.
// Creates three throw-away accounts, exercises consent and visibility, then removes everything it created.
// Never targets a hosted site and never reads player files.   node tools/verify_meets_flow.mjs
import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { readdirSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import path from 'node:path';

const base = 'http://127.0.0.1:5173';
const d1Dir = path.join('platform', '.wrangler', 'state', 'v3', 'd1', 'miniflare-D1DatabaseObject');
const db = new DatabaseSync(path.join(d1Dir, readdirSync(d1Dir).find(name => name.endsWith('.sqlite') && name !== 'metadata.sqlite')));
const now = Math.floor(Date.now() / 1000);
const run = randomBytes(4).toString('hex');
const people = {};
let passed = 0;
function check(label, condition) { assert(condition, label); passed++; console.log('PASS', label); }

function account(key, name) {
  const token = randomBytes(24).toString('base64url');
  const id = `mtest-${run}-${key}`;
  db.prepare("INSERT INTO et_users(id,discord_id,username,display_name,avatar,created_at,last_login_at) VALUES(?,NULL,?,?,NULL,?,?)").run(id, id, name, now, now);
  db.prepare("INSERT INTO et_sessions(token_hash,user_id,created_at,expires_at) VALUES(?,?,?,?)").run(createHash('sha256').update(token).digest('hex'), id, now, now + 3600);
  return { id, name, cookie: `et_session=${token}`, producerId: id, charId: `Player-${run}-${key}` };
}
async function call(who, method, url, body) {
  const response = await fetch(base + url, { method, headers: { Origin: base, Cookie: who.cookie, ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
  return { status: response.status, data: await response.json().catch(() => ({})) };
}
const game = { product: 'forever', build: 'integration-test', interface: 16001, region: 'test', realm: 'Test' };
const event = (who, suffix, kind, payload) => ({ schemaVersion: 1, eventId: `${who.producerId}:${suffix}`, producerId: who.producerId, origin: 'local_observation', kind, observedAt: now, game,
  character: { id: who.charId, name: who.name, realm: 'Test', classId: 8, raceId: 1, level: 30 }, payload, evidence: 'api_snapshot' });
async function upload(who, events) {
  const scopes = ['own_character', 'own_track'];
  const consent = await call(who, 'POST', '/api/consents', { producerId: who.producerId, consentEpoch: 1, since: now - 600, scopes });
  assert(consent.status < 300, 'consent: ' + JSON.stringify(consent.data));
  who.grantId = consent.data.grant.id;
  return call(who, 'POST', '/api/uploads', { grantId: who.grantId, export: { schemaVersion: 1, enabled: true, producerId: who.producerId, consentEpoch: 1, since: now - 600, scopes, events } });
}
const route = (x, y) => ({ mapId: 1429, mapSystem: 'ui_map', startedAt: now - 120, points: [[0, x - 0.02, y], [60, x - 0.01, y], [120, x, y]] });
const meetBody = (audience, extra = {}) => ({ kind: 'meet', title: 'Sraz u hostince', note: 'Přijďte včas', mapId: 1429, x: 0.42, y: 0.65, startsAt: null, durationMin: 120, audience, ...extra });

try {
  for (const [key, name] of [['gm', 'Aria'], ['bob', 'Bran'], ['eve', 'Eve']]) people[key] = account(key, `${name}${run}`);
  const { gm, bob, eve } = people;
  for (const who of [gm, bob, eve]) check(`${who.name} has a character from the addon`, (await upload(who, [event(who, 't', 'track.path', route(0.5, 0.5))])).data.accepted === 1);
  const profile = async who => (await call(who, 'GET', '/api/me')).data.profiles[0].id;
  const [pg, pb, pe] = [await profile(gm), await profile(bob), await profile(eve)];

  const made = await call(gm, 'POST', '/api/circles', { name: `Pátek ${run}`, profileId: pg, share: 'trail' });
  check('group created with an invite code the owner can read', made.status === 201 && made.data.code.length === 10);
  const owner = (await call(gm, 'GET', '/api/guild')).data.circles[0];
  check('only the owner sees the invite code', /^[A-Z0-9]{5}-[A-Z0-9]{5}$/.test(owner.inviteCode));
  check('a wrong code is refused', (await call(bob, 'POST', '/api/circles/join', { code: 'AAAAAAAAAA', profileId: pb })).data.error.code === 'invalid_code');
  check('somebody else\'s character cannot join', (await call(bob, 'POST', '/api/circles/join', { code: made.data.code, profileId: pg })).status === 404);
  check('bob joins with the code and shares his last position', (await call(bob, 'POST', '/api/circles/join', { code: made.data.code, profileId: pb, share: 'last' })).status === 200);
  const asBob = (await call(bob, 'GET', '/api/guild')).data.circles[0];
  check('bob sees the group, but not the invite code', asBob.inviteCode === null && asBob.members.length === 2);
  check('bob sees the owner\'s position (the owner shares the route)', asBob.members.find(m => m.profileId === pg)?.position?.mapId === 1429);
  const asGm = (await call(gm, 'GET', '/api/guild')).data.circles[0];
  check('the owner sees bob\'s last position', Math.abs(asGm.members.find(m => m.profileId === pb).position.x - 0.5) < 1e-9);
  check('the owner cannot load a route bob does not share', (await call(gm, 'GET', `/api/circles/${made.data.code && asGm.id}/trail?profile=${pb}&hours=24`)).status === 403);
  check('eve is not in the group and sees none', (await call(eve, 'GET', '/api/guild')).data.circles.length === 0);

  const meet = await call(gm, 'POST', '/api/meets', meetBody({ kind: 'circle', id: asGm.id }, { capacity: 2 }));
  check('a group meet is created', meet.status === 201 && meet.data.meet.going === 1);
  check('bob (in the group) sees it', (await call(bob, 'GET', '/api/meets')).data.meets.length === 1);
  check('eve (outside) does not', (await call(eve, 'GET', '/api/meets')).data.meets.length === 0);
  check('eve cannot create a meet for a group she is not in', (await call(eve, 'POST', '/api/meets', meetBody({ kind: 'circle', id: asGm.id }))).status === 403);
  check('bob answers going', (await call(bob, 'POST', `/api/meets/${meet.data.meet.id}/rsvp`, { status: 'going' })).data.meet.going === 2);
  check('eve cannot answer a meet she cannot see', (await call(eve, 'POST', `/api/meets/${meet.data.meet.id}/rsvp`, { status: 'going' })).status === 404);
  check('bob cannot cancel the owner\'s meet', (await call(bob, 'PATCH', `/api/meets/${meet.data.meet.id}`, { cancel: true })).status === 404);

  const link = await call(gm, 'POST', '/api/meets', meetBody({ kind: 'link' }, { title: 'Veřejný sraz', kind: 'trade', data: { wanted: [{ item: 2318, qty: 5 }], offered: [{ item: 2589, qty: 20 }] } }));
  check('a link meet returns its code to the creator', /^[A-Z0-9]{10}$/.test(link.data.meet.linkCode));
  check('eve does not see it without the link', (await call(eve, 'GET', '/api/meets')).data.meets.length === 0);
  const opened = await call(eve, 'GET', `/api/meets?code=${link.data.meet.linkCode}`);
  check('with the link eve sees it, without the code', opened.data.opened === link.data.meet.id && opened.data.meets[0].linkCode === null && opened.data.meets[0].data.wanted[0].item === 2318);
  check('a wrong link is refused', (await call(eve, 'GET', '/api/meets?code=AAAAAAAAAA')).status === 404);

  check('the owner cancels a meet', (await call(gm, 'PATCH', `/api/meets/${link.data.meet.id}`, { cancel: true })).status === 200 && (await call(eve, 'GET', '/api/meets')).data.meets.length === 0);
  check('invalid meet data is refused', (await call(gm, 'POST', '/api/meets', { ...meetBody({ kind: 'link' }), x: 4 })).status === 400);

  check('the owner removes bob', (await call(gm, 'POST', `/api/circles/${asGm.id}`, { action: 'kick', target: pb })).status === 200);
  check('bob no longer sees the group meet', (await call(bob, 'GET', '/api/meets')).data.meets.filter(m => m.audience.kind === 'circle').length === 0);
  check('the owner closes the group', (await call(gm, 'POST', `/api/circles/${asGm.id}`, { action: 'close' })).status === 200 && (await call(gm, 'GET', '/api/guild')).data.circles.length === 0);
} finally {
  for (const who of Object.values(people)) {
    await fetch(base + '/api/me/data', { method: 'DELETE', headers: { Origin: base, Cookie: who.cookie } }).catch(() => {});
    for (const table of ['et_circle_members', 'et_meet_rsvps', 'et_meet_access', 'et_meets']) db.prepare(`DELETE FROM ${table} WHERE user_id=?`).run(who.id);
    db.prepare('DELETE FROM atlas_sources WHERE user_id=?').run(who.id);
    db.prepare('DELETE FROM atlas_grants WHERE user_id=?').run(who.id);
    db.prepare('DELETE FROM et_sessions WHERE user_id=?').run(who.id);
    db.prepare('DELETE FROM et_users WHERE id=?').run(who.id);
  }
  db.prepare("DELETE FROM et_circles WHERE name LIKE ?").run(`Pátek ${run}`);
  const like = `mtest-${run}-%`;
  const left = db.prepare("SELECT (SELECT COUNT(*) FROM et_users WHERE id LIKE ?) users, (SELECT COUNT(*) FROM atlas_observations WHERE user_id LIKE ?) obs, (SELECT COUNT(*) FROM et_meets WHERE user_id LIKE ?) meets, (SELECT COUNT(*) FROM et_circles WHERE owner_user_id LIKE ?) circles").get(like, like, like, like);
  console.log('cleanup left:', JSON.stringify(left));
  assert.deepEqual({ ...left }, { users: 0, obs: 0, meets: 0, circles: 0 });
}
console.log(`\n${passed} checks passed`);
