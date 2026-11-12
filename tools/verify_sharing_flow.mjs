// Loopback-only integration test of "who may see my live position": friends, signed-in visitors, visitors who are not signed in.
// Creates throw-away accounts with a device and a live position each, exercises every choice over the real HTTP API and the
// local D1 file, then removes everything it created. Never targets a hosted site and never reads player files.
//   node tools/verify_sharing_flow.mjs
import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';

const endpoint = new URL(process.env.EVERTALLY_TEST_URL || 'http://127.0.0.1:5173');
if (endpoint.protocol !== 'http:' || endpoint.hostname !== '127.0.0.1') throw Error('This fixture test only supports loopback HTTP.');
const base = endpoint.origin;
const dir = 'platform/.wrangler/state/v3/d1/miniflare-D1DatabaseObject';
const file = path.join(dir, readdirSync(dir).find(n => n.endsWith('.sqlite') && n !== 'metadata.sqlite'));
const db = new DatabaseSync(file);
for (const migration of ['0005_live_positions.sql', '0006_sharing.sql', '0007_game_connections.sql']) db.exec(readFileSync(`platform/drizzle/${migration}`, 'utf8'));
const run = randomBytes(5).toString('hex');
const users = [];
const at = () => Math.floor(Date.now() / 1000);
const hash = value => createHash('sha256').update(value).digest('hex');
let passed = 0;
const check = (label, condition) => { assert(condition, label); passed++; console.log('PASS', label); };

function account(name) {
  const id = `stest-${run}-${name}`, cookie = randomBytes(24).toString('hex'), token = 'etd_' + randomBytes(32).toString('hex');
  db.prepare('INSERT INTO et_users(id,username,display_name,created_at,last_login_at) VALUES(?,?,?,?,?)').run(id, id, 'Fixture' + name, at(), at());
  db.prepare('INSERT INTO et_sessions(token_hash,user_id,created_at,expires_at) VALUES(?,?,?,?)').run(hash(cookie), id, at(), at() + 3600);
  db.prepare('INSERT INTO et_devices(id,user_id,name,token_hash,scopes,created_at) VALUES(?,?,?,?,?,?)').run(id, id, 'test', hash(token), JSON.stringify(['own_track', 'own_character']), at());
  const user = { id, cookie: `et_session=${cookie}`, token, producer: id, name: 'Fixture' + name };
  users.push(user);
  return user;
}
async function call(user, method, url, body, device = false, attempt = 0) {
  const headers = { Origin: base };
  if (user) headers[device ? 'Authorization' : 'Cookie'] = device ? `Bearer ${user.token}` : user.cookie;
  if (body) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + url, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await response.text();
  // Local workerd may restart while loading a route for the first time; never retry actual API/database errors.
  if (response.status === 503 && text.includes('Your worker restarted mid-request') && attempt < 2) {
    return call(user, method, url, body, device, attempt + 1);
  }
  try { return { status: response.status, data: JSON.parse(text) }; }
  catch { throw Error(`${method} ${url} returned ${response.status}: ${text.slice(0, 150)}`); }
}
const packet = (user, x = 42000) => ({ v: 1, p: user.producer, e: 1, s: at() - 60, b: 20, t: at(), c: { id: 'Player-' + user.id, name: user.name, realm: 'Test', classId: 8, raceId: 1, level: 20 },
  g: { product: 'forever', build: 'test', interface: 16001, region: 'test', realm: 'Test' }, m: 1426, x, y: 65000 });
const others = async user => (await call(user, 'GET', '/api/live')).data.others ?? [];
const publicList = async () => (await call(null, 'GET', '/api/public-live'));

try {
  const a = account('a'), b = account('b'), c = account('c');
  for (const user of [a, b, c]) check(`live position of ${user.name} accepted`, (await call(user, 'POST', '/api/device/live', packet(user), true)).status === 200);

  check('by default nobody sees anybody (signed in or not)', (await others(b)).length === 0 && (await publicList()).data.players.every(p => p.name !== a.name));
  check('the choices start off', JSON.stringify((await call(a, 'GET', '/api/sharing')).data.sharing) === JSON.stringify({ friends: false, signedIn: false, public: false }));
  check('a change needs the website (same origin)', (await fetch(base + '/api/sharing', { method: 'POST', headers: { Cookie: a.cookie, 'Content-Type': 'application/json' }, body: '{"public":true}' })).status === 403);
  check('sharing needs a sign-in', (await fetch(base + '/api/sharing')).status === 401);

  // everyone, also visitors who are not signed in
  check('public on', (await call(a, 'POST', '/api/sharing', { public: true })).data.sharing.public === true);
  const visitor = await publicList();
  const seen = visitor.data.players.find(p => p.name === a.name);
  check('a visitor who is not signed in sees the position', visitor.status === 200 && seen && seen.mapId === 1426 && seen.x === 0.42);
  check('the public list carries no account identifier and no reason', !('userId' in seen) && !('audience' in seen) && !JSON.stringify(visitor.data).includes(a.id));
  check('a signed-in viewer sees it as public', (await others(b)).some(p => p.name === a.name && p.audience === 'public'));
  check('the owner does not get their own character as a stranger', !(await others(a)).some(p => p.name === a.name));
  check('the visitor never sees an account that shares nothing', !visitor.data.players.some(p => p.name === b.name));

  // every signed-in visitor, nobody else
  await call(a, 'POST', '/api/sharing', { public: false, signedIn: true });
  check('signed-in only: a visitor sees nothing of it', !(await publicList()).data.players.some(p => p.name === a.name));
  check('signed-in only: a signed-in viewer does', (await others(c)).some(p => p.name === a.name && p.audience === 'signed_in'));

  // friends, both agreed
  await call(a, 'POST', '/api/sharing', { signedIn: false, friends: true });
  check('friends only: a stranger sees nothing', (await others(b)).length === 0 && (await others(c)).length === 0);
  check('asking for a name that does not exist looks the same as asking for one that does', (await call(b, 'POST', '/api/friends', { name: 'nobody-' + run })).data.status === 'sent');
  check('the request goes out', (await call(b, 'POST', '/api/friends', { name: a.id.toUpperCase() })).data.status === 'sent');
  check('a request alone shows nothing', (await others(b)).length === 0);
  const incoming = (await call(a, 'GET', '/api/friends')).data.incoming;
  check('the other side sees the request with a name', incoming.length === 1 && incoming[0].userId === b.id && incoming[0].name === b.name);
  check('the asker cannot accept their own request', (await call(b, 'POST', `/api/friends/${a.id}`, { action: 'accept' })).status === 404);
  check('the answer makes friends', (await call(a, 'POST', `/api/friends/${b.id}`, { action: 'accept' })).status === 200);
  check('a friend sees it, as a friend', (await others(b)).some(p => p.name === a.name && p.audience === 'friends'));
  check('a third account still sees nothing', (await others(c)).length === 0);
  check('the friend who shares nothing is not visible back', !(await others(a)).some(p => p.name === b.name));
  check('friends are listed on both sides', (await call(b, 'GET', '/api/friends')).data.friends.some(f => f.userId === a.id) && (await call(a, 'GET', '/api/friends')).data.friends.some(f => f.userId === b.id));

  // ending it works at once
  await call(a, 'POST', '/api/friends/' + b.id, { action: 'remove' });
  check('removing a friend hides the position at once', (await others(b)).length === 0);
  await call(b, 'POST', '/api/friends', { name: a.id });
  await call(a, 'POST', `/api/friends/${b.id}`, { action: 'accept' });
  check('friends again', (await others(b)).length === 1);
  await call(a, 'POST', '/api/sharing', { friends: false });
  check('switching the choice off hides it at once', (await others(b)).length === 0);

  // consent and device still decide
  await call(a, 'POST', '/api/sharing', { public: true });
  check('public again', (await publicList()).data.players.some(p => p.name === a.name));
  db.prepare('UPDATE et_devices SET revoked_at=? WHERE id=?').run(at(), a.id);
  check('a disconnected device ends it', !(await publicList()).data.players.some(p => p.name === a.name));
  console.log(`PASS sharing HTTP: ${passed} checks`);
} finally {
  for (const user of users) {
    const erased = await call(user, 'DELETE', '/api/me/data').catch(error => ({ status: 0, data: { message: error.message } }));
    assert.equal(erased.status, 200, JSON.stringify(erased));
    for (const table of ['et_sharing', 'et_live_positions', 'et_devices', 'et_sessions']) db.prepare(`DELETE FROM ${table} WHERE user_id=?`).run(user.id);
    db.prepare('DELETE FROM et_friends WHERE user_a=? OR user_b=?').run(user.id, user.id);
    db.prepare('DELETE FROM et_users WHERE id=?').run(user.id);
  }
  db.close();
}
