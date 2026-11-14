// Loopback-only integration test of the leaderboard: a public character, its item level and guild shown only after
// the player turns them on in Account, the faction filter and the order of equal levels.
// Creates throw-away accounts with a grant, a character, an armory snapshot and a guild snapshot directly in the
// local D1 file, exercises the real HTTP API, then removes everything it created. Never targets a hosted site and
// never reads player files.
//   node tools/verify_ranking_flow.mjs            run the checks and clean up
//   node tools/verify_ranking_flow.mjs --keep     leave the fixture in place (to look at it in a browser); prints a session cookie
//   node tools/verify_ranking_flow.mjs --cleanup  remove every fixture this script ever left behind
import assert from 'node:assert/strict';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { readdirSync } from 'node:fs';
import path from 'node:path';

const endpoint = new URL(process.env.EVERTALLY_TEST_URL || 'http://127.0.0.1:5173');
if (endpoint.protocol !== 'http:' || endpoint.hostname !== '127.0.0.1') throw Error('This fixture test only supports loopback HTTP.');
const base = endpoint.origin;
const dir = 'platform/.wrangler/state/v3/d1/miniflare-D1DatabaseObject';
const file = path.join(dir, readdirSync(dir).find(n => n.endsWith('.sqlite') && n !== 'metadata.sqlite'));
const db = new DatabaseSync(file);
const PREFIX = 'rtest-';
const keep = process.argv.includes('--keep');
const at = () => Math.floor(Date.now() / 1000);
const hash = value => createHash('sha256').update(value).digest('hex');

function cleanup(like = `${PREFIX}%`) {
  db.prepare('DELETE FROM atlas_observations WHERE user_id LIKE ?').run(like);
  for (const table of ['atlas_profiles', 'atlas_grants', 'atlas_sources', 'atlas_uploads', 'et_devices', 'et_sessions']) db.prepare(`DELETE FROM ${table} WHERE user_id LIKE ?`).run(like);
  db.prepare('DELETE FROM et_users WHERE id LIKE ?').run(like);
}
if (process.argv.includes('--cleanup')) { cleanup(); console.log('Removed every leaderboard fixture.'); process.exit(0); }

const columns = db.prepare("PRAGMA table_info('atlas_profiles')").all().map(row => row.name);
if (!columns.includes('show_item_level')) throw Error('Apply platform/drizzle/0009_ranking_details.sql to the local database first.');

const run = randomBytes(4).toString('hex');
let passed = 0, n = 0;
const check = (label, condition) => { assert(condition, label); passed++; console.log('PASS', label); };

// gear of the website's item index: 647 Destiny (57, two-handed), 1 is not gear
const GEAR = [{ slot: 1, itemId: 647 }, { slot: 5, itemId: 647 }, { slot: 16, itemId: 647 }];
function account(name, character) {
  const id = `${PREFIX}${run}-${name}`, cookie = randomBytes(24).toString('hex');
  db.prepare('INSERT INTO et_users(id,username,display_name,created_at,last_login_at) VALUES(?,?,?,?,?)').run(id, id, 'Fixture' + name, at(), at());
  db.prepare('INSERT INTO et_sessions(token_hash,user_id,created_at,expires_at) VALUES(?,?,?,?)').run(hash(cookie), id, at(), at() + 3600);
  db.prepare('INSERT INTO atlas_grants(id,user_id,producer_id,consent_epoch,since,scopes,created_at) VALUES(?,?,?,?,?,?,?)')
    .run('g-' + id, id, 'src-' + id, 1, 0, JSON.stringify(['own_character', 'own_runs', 'guild_share']), at());
  db.prepare('INSERT INTO atlas_profiles(id,user_id,producer_id,character_key,name,realm,class_id,race_id,level,"public",last_seen) VALUES(?,?,?,?,?,?,?,?,?,0,?)')
    .run('p-' + id, id, 'src-' + id, 'k-' + id, character.name, 'Fixture', character.classId, character.raceId, character.level, at());
  const observe = (kind, scope, payload) => db.prepare("INSERT INTO atlas_observations(id,user_id,producer_id,event_id,grant_id,kind,scope,observed_at,profile_id,payload,game,evidence) VALUES(?,?,?,?,?,?,?,?,?,?,'{}','api_snapshot')")
    .run(`o-${id}-${++n}`, id, 'src-' + id, `e-${id}-${n}`, 'g-' + id, kind, scope, at(), 'p-' + id, JSON.stringify(payload));
  observe('character.snapshot', 'own_character', { level: character.level, classId: character.classId, raceId: character.raceId, name: character.name, realm: 'Fixture' });
  if (character.gear) observe('armory.snapshot', 'own_character', { equipped: character.gear, bags: [], stats: {}, talents: [], professions: [] });
  if (character.guild) observe('guild.snapshot', 'guild_share', { guildName: character.guild, rankIndex: 4 });
  return { id, profile: 'p-' + id, cookie: `et_session=${cookie}`, raw: cookie, name: character.name };
}
async function call(user, method, url, body, attempt = 0) {
  const headers = { Origin: base };
  if (user) headers.Cookie = user.cookie;
  if (body) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + url, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await response.text();
  if (response.status === 503 && text.includes('Your worker restarted mid-request') && attempt < 2) return call(user, method, url, body, attempt + 1);
  try { return { status: response.status, data: JSON.parse(text) }; }
  catch { throw Error(`${method} ${url} returned ${response.status}: ${text.slice(0, 150)}`); }
}
const board = async (query = 'metric=level') => (await call(null, 'GET', `/api/leaderboards?${query}`)).data.entries;
const mine = (entries, user) => entries.find(e => e.character.id === user.profile);
const patch = (user, profile, body) => call(user, 'PATCH', `/api/profiles/${encodeURIComponent(profile)}`, body);

try {
  // two level-60 characters: an Alliance Skyborne with gear and a guild, and a Horde orc without them
  const a = account('a', { name: `Aerin${run}`, classId: 11, raceId: 95, level: 60, gear: GEAR, guild: 'Dawn Watch' });
  const b = account('b', { name: `Brok${run}`, classId: 1, raceId: 2, level: 60 });

  check('a private character is not on the leaderboard', !mine(await board(), a));
  check('publishing needs the owner: another account cannot', (await patch(b, a.profile, { public: true })).status === 404);
  check('publishing needs a sign-in', (await patch(null, a.profile, { public: true })).status === 401);
  check('an empty change is refused', (await patch(a, a.profile, {})).status === 400);
  for (const user of [a, b]) check(`${user.name} can publish`, (await patch(user, user.profile, { public: true })).data.profile.public === true);

  let entry = mine(await board(), a);
  check('a public character appears with level and race', entry?.character.level === 60 && entry.character.raceId === 95);
  check('item level and guild stay hidden until turned on', entry.itemLevel === undefined && entry.guild === undefined);
  const turned = (await patch(a, a.profile, { showItemLevel: true })).data.profile;
  check('the item level choice is saved and returned', turned.showItemLevel === true && turned.showGuild === false && turned.public === true);
  entry = mine(await board(), a);
  // three slots of 57, the two-hander also fills the empty off hand: 4 × 57 / 17 = 13.4 → 13
  check('the item level shows as the computed average', entry.itemLevel === 13);
  check('the gear itself never leaves the armory', !JSON.stringify(entry).includes('647'));
  check('the guild still stays hidden', entry.guild === undefined);
  await patch(a, a.profile, { showGuild: true });
  check('the guild shows after it is turned on', mine(await board(), a)?.guild === 'Dawn Watch');
  const me = (await call(a, 'GET', '/api/me')).data.profiles.find(p => p.id === a.profile);
  check('Account lists both choices', me?.showItemLevel === true && me?.showGuild === true);

  const both = await board();
  check('equal levels: the character with an item level ranks first', both.findIndex(e => e.character.id === a.profile) < both.findIndex(e => e.character.id === b.profile));
  check('faction filter: Skyborne 95 is Alliance', mine(await board('metric=level&faction=alliance'), a) && !mine(await board('metric=level&faction=alliance'), b));
  check('faction filter: the orc is Horde', mine(await board('metric=level&faction=horde'), b) && !mine(await board('metric=level&faction=horde'), a));

  // the character page: place on the board and the details the player chose to show
  const page = (await call(null, 'GET', `/api/profiles/${encodeURIComponent(a.profile)}`)).data;
  check('the character page shows its place, item level and guild', page.ranks?.overall === 1 && page.ranks.class === 1 && page.itemLevel === 13 && page.guild === 'Dawn Watch');
  check('the character page never carries the gear', !JSON.stringify(page).includes('647'));

  // publishing from the game: a character.publish event through the real upload API
  const c = account('c', { name: `Cael${run}`, classId: 3, raceId: 96, level: 42 });
  const grant = randomUUID();
  db.prepare('INSERT INTO atlas_grants(id,user_id,producer_id,consent_epoch,since,scopes,created_at) VALUES(?,?,?,?,?,?,?)').run(grant, c.id, 'game-' + c.id, 1, 0, JSON.stringify(['own_character']), at());
  const upload = (eventId, payload, observedAt = at()) => call(c, 'POST', '/api/uploads', { grantId: grant, export: { schemaVersion: 1, enabled: true, producerId: 'game-' + c.id, consentEpoch: 1, since: 0, scopes: ['own_character'],
    events: [{ schemaVersion: 1, eventId, producerId: 'game-' + c.id, origin: 'local_observation', kind: 'character.publish', observedAt, game: { product: 'forever', build: 'test', interface: 11507, region: 'eu', realm: 'Fixture' },
      character: { id: 'Player-' + c.id, name: c.name, realm: 'Fixture', classId: 3, raceId: 96, level: 42 }, payload, evidence: 'api_snapshot' }] } });
  check('a choice from the game is accepted', (await upload('pub-1', { public: true, showItemLevel: false, chosenAt: at() })).status === 200);
  const gameProfile = db.prepare('SELECT id,"public" AS p,visibility_at AS v FROM atlas_profiles WHERE user_id=? AND producer_id=?').get(c.id, 'game-' + c.id);
  check('the game choice published the character', gameProfile?.p === 1 && gameProfile.v > 0);
  check('a Windshaper Skyborne from the game is on the Horde board', (await board('metric=level&faction=horde')).some(e => e.character.id === gameProfile.id));
  check('the website can still make it private', (await patch(c, gameProfile.id, { public: false })).data.profile.public === false);
  check('an older game choice replayed later does not publish it again', (await upload('pub-old', { public: true, chosenAt: at() - 3600 }, at() - 60)).status === 200
    && db.prepare('SELECT "public" AS p FROM atlas_profiles WHERE id=?').get(gameProfile.id).p === 0);

  await patch(a, a.profile, { public: false });
  check('making the character private again removes it with its details', !mine(await board(), a));
  await patch(a, a.profile, { public: true });
  db.prepare('UPDATE atlas_grants SET revoked_at=? WHERE user_id=?').run(at(), a.id);
  entry = mine(await board(), a);
  check('a revoked consent hides the character and its details', !entry || (entry.itemLevel === undefined && entry.guild === undefined));
  if (keep) {
    db.prepare('UPDATE atlas_grants SET revoked_at=NULL WHERE user_id=?').run(a.id);
    console.log(`\nFixture kept (run ${run}). In the browser on ${base}: document.cookie = "et_session=${a.raw}; path=/"`);
    console.log('Remove it with: node tools/verify_ranking_flow.mjs --cleanup');
  }
  console.log(`\n${passed} checks passed.`);
} finally {
  if (!keep) cleanup(`${PREFIX}${run}-%`);
}
