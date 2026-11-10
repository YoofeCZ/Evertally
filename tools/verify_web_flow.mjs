// Local integration check. Never reads player files, never targets a hosted site.
import assert from 'node:assert/strict';
import { writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const base = 'http://127.0.0.1:5173';
let cookie = '';
const checks = [];
async function call(path, options = {}) {
  const response = await fetch(base + path, {
    ...options,
    headers: { Origin: base, ...options.headers, ...(cookie ? { Cookie: cookie } : {}) },
    redirect: 'manual',
  });
  const body = await response.text();
  let data;
  try { data = JSON.parse(body); } catch { data = { raw: body.slice(0, 180) }; }
  return { status: response.status, data, headers: response.headers };
}
const post = (path, data) => call(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
function check(label, condition) { assert(condition, label); checks.push(label); console.log('PASS', label); }

check('anonymous private endpoint rejects', (await call('/api/me')).status === 401);
const login = await call('/auth/dev?return_to=%2F');
const cookies = login.headers.getSetCookie();
assert(cookies.length, 'Local Sites auth cookie was not provided');
cookie = cookies.map(value => value.split(';')[0]).join('; ');
const me = await call('/api/me');
check('local preview sign-in', me.status === 200 && me.data.user);
assert(me.data.eventCount === 0, 'Integration test requires a fresh local account database; refusing to delete existing data');

const now = Math.floor(Date.now() / 1000);
const producerId = 'integration-' + crypto.randomUUID();
const character = { id: producerId + ':self', name: 'Synteticky test', realm: 'Test', classId: 7, raceId: 6, level: 20 };
const event = (suffix, kind, payload) => ({ schemaVersion: 1, eventId: `${producerId}:${suffix}`, producerId, origin: 'local_observation', kind,
  observedAt: now, game: { product: 'forever', build: 'integration-test', interface: 16001, region: 'test', realm: 'Test' }, character,
  payload, evidence: 'api_event' });
const envelope = { schemaVersion: 1, enabled: true, producerId, consentEpoch: 1, since: now - 60,
  scopes: ['world_facts', 'own_runs', 'own_character', 'own_professions'], events: [
    event('quest', 'quest.turned_in', { questId: 182, title: 'Synteticky quest', xp: 100, money: 0 }),
    event('npc', 'npc.observed', { npcId: 706, name: 'Synteticky NPC', mapId: 1, x: 0.4, y: 0.5, positionMethod: 'player_interaction' }),
    event('run', 'run.finished', { runId: producerId + ':run', instanceId: 36, name: 'Synteticky dungeon', instanceType: 'party', difficultyId: 1,
      startedAt: now - 30, endedAt: now, durationMs: 30000, status: 'completed', completion: 'last_boss', rankEligible: true, bossCount: 1 }),
    event('prof', 'profession.snapshot', { professionId: 171, name: 'Synteticka profese', skill: 1, maxSkill: 75, recipes: [] }),
  ] };

let modified = false;
try {
  const grantResult = await post('/api/consents', { producerId, consentEpoch: 1, since: now - 60, scopes: envelope.scopes });
  check('explicit scoped consent grant', grantResult.status < 300 && grantResult.data.grant?.id);
  modified = true;
  const grantId = grantResult.data.grant.id;
  const uploaded = await post('/api/uploads', { grantId, export: envelope });
  check('four own events accepted', uploaded.status < 300 && uploaded.data.accepted === 4);
  const twice = await post('/api/uploads', { grantId, export: envelope });
  check('duplicate upload does not multiply events', twice.status < 300 && twice.data.duplicates === 4 && twice.data.accepted === 0);
  const bulk = { ...envelope, events: Array.from({ length: 500 }, (_, index) => event('bulk-' + index, 'quest.turned_in', { questId: 300000 + index, title: 'Synteticky bulk quest', xp: 1 })) };
  const bulkResult = await post('/api/uploads', { grantId, export: bulk });
  check('500-event batch accepted through real HTTP and D1', bulkResult.status < 300 && bulkResult.data.accepted === 500);
  const bulkAgain = await post('/api/uploads', { grantId, export: bulk });
  check('500-event replay is fully idempotent', bulkAgain.status < 300 && bulkAgain.data.duplicates === 500 && bulkAgain.data.accepted === 0);
  const own = await call('/api/runs?mine=1');
  check('own run is persisted', own.status === 200 && own.data.runs.length === 1);
  check('unverified rank eligibility cannot be forged', own.data.runs[0].rankEligible === false);
  const publicRuns = await call('/api/runs');
  check('profile is private by default', publicRuns.status === 200 && publicRuns.data.runs.length === 0);
  const current = await call('/api/me');
  assert(current.data.profiles.length === 1);
  const profile = current.data.profiles[0];
  const publish = await call('/api/profiles/' + profile.id, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ public: true }) });
  check('explicit profile visibility change', publish.status < 300);
  check('published own run visible', (await call('/api/runs')).data.runs.length === 1);
  check('world facts projected into atlas', (await call('/api/atlas')).data.entities.length >= 1);
  const forged = structuredClone(envelope); forged.events[0].origin = 'peer';
  check('peer data rejected at upload boundary', (await post('/api/uploads', { grantId, export: forged })).status >= 400);
  const revoke = await call('/api/consents/' + grantId, { method: 'DELETE' });
  check('grant revocation', revoke.status < 300);
  check('revoked grant rejects old file', (await post('/api/uploads', { grantId, export: envelope })).status === 403);
  check('revoked epoch cannot be reused', (await post('/api/consents', { producerId, consentEpoch: 1, since: now - 60, scopes: envelope.scopes })).status >= 400);
} finally {
  if (modified) {
    const deletion = await call('/api/me/data', { method: 'DELETE' });
    check('synthetic account data removed after integration check', deletion.status < 300);
    check('no synthetic public runs remain', (await call('/api/runs')).data.runs.length === 0);
  }
}
await writeFile(fileURLToPath(new URL('../releases/web-integration-verification.json', import.meta.url)), JSON.stringify({ checkedAt: new Date().toISOString(), scope: 'local preview, synthetic data only', checks }, null, 2));
