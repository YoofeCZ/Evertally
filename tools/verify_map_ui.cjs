// Isolated headless browser, synthetic account and API. Never touches the user's browser or game.
// Requires Playwright via NODE_PATH or PLAYWRIGHT_MODULE; EVERTALLY_TEST_URL can point at a local build or the public site.
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

(async () => {
  const browser = await chromium.launch({channel: 'msedge', headless: true});
  try {
    const page = await browser.newPage({viewport: {width: 1440, height: 960}});
    let samples = 0, stale = false, partyPresent = true;
    let friendMutations = 0;
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => {
      localStorage.setItem('et_lang', 'cs');
      localStorage.setItem('evertally.map.layers', JSON.stringify({route: true, players: false}));
    });
    await page.route('**/api/**', async route => {
      const pathname = new URL(route.request().url()).pathname;
      if (pathname.startsWith('/api/friends') && route.request().method() !== 'GET') friendMutations++;
      let data;
      if (pathname === '/api/status') data = {version: '0.7.0', user: {id: 'fixture', displayName: 'Test', avatarUrl: null}, auth: {discord: true}};
      else if (pathname === '/api/track') data = {paths: [], characters: [{id: 'p', name: 'LiveFixture', classId: 8, level: 20}], truncated: false};
      else if (pathname === '/api/live') {
        const at = Math.floor(Date.now() / 1000) - (stale ? 60 : 0);
        data = {own: [{profileId: 'p', name: 'LiveFixture', classId: 8, mapId: 1429, x: .42 + samples++ * .003, y: .65, at, live: true}], peers: [], others: [
          {profileId: 'friend', name: 'FriendFixture', classId: 11, mapId: 1429, x: .45, y: .63, at, audience: 'friends'},
          ...(partyPresent ? [{profileId: 'group', name: 'GroupFixture', classId: 5, mapId: 1429, x: .47, y: .61, at, audience: 'group'}] : []),
          {profileId: 'stranger', name: 'StrangerFixture', classId: 1, mapId: 1429, x: .49, y: .67, at, audience: 'public'},
        ]};
      }
      else if (pathname === '/api/guild') data = {guilds: [], circles: []};
      else if (pathname === '/api/me') data = {profiles: [{id: 'p', name: 'LiveFixture', classId: 8, level: 20}]};
      else if (pathname === '/api/sharing') data = {sharing: {friends: false, signedIn: false, public: false}};
      else if (pathname === '/api/friends') data = {friends: [], incoming: [], outgoing: []};
      else return route.continue();
      await route.fulfill({contentType: 'application/json', body: JSON.stringify(data)});
    });
    await page.goto((process.env.EVERTALLY_TEST_URL || 'http://127.0.0.1:5185') + '/#atlas/elwynn-forest', {waitUntil: 'domcontentloaded'});
    const panel = page.getByRole('region', {name: 'Trasy a skupiny'});
    // A section with aria-label may be exposed as a region only once its client content mounts.
    await page.getByText('ŽIVĚ — poloha se aktualizuje').waitFor();
    const section = await panel.count() ? panel : page.locator('.people-panel').first();
    const header = section.locator('header');
    const before = await section.boundingBox();
    await page.getByRole('button', {name: 'Sbalit panel', exact: true}).first().click();
    const collapsed = await section.boundingBox();
    assert(collapsed.height < 80 && collapsed.height < before.height, 'Panel must collapse');
    await page.getByRole('button', {name: 'Rozbalit panel', exact: true}).first().click();
    const box = await header.boundingBox();
    await page.mouse.move(box.x + 25, box.y + 15);
    await page.mouse.down();
    await page.mouse.move(box.x + 105, box.y + 55, {steps: 8});
    await page.mouse.up();
    const moved = await section.boundingBox();
    assert(moved.x - before.x > 60, 'Header drag must move the panel');
    assert(await page.evaluate(() => Boolean(localStorage.getItem('evertally.map.panel.people'))), 'Drag position must persist');
    await header.dblclick({position: {x: 25, y: 15}});
    await page.waitForFunction(expected => {
      const element = document.querySelector('section[aria-label="Trasy a skupiny"]');
      return element && Math.abs(element.getBoundingClientRect().x - expected) < 2;
    }, before.x);
    const reset = await section.boundingBox();
    assert(Math.abs(reset.x - before.x) < 2, 'Double click must reset panel position');
    await page.getByRole('button', {name: 'Ukázat živou polohu', exact: true}).click();
    const marker = page.locator('.person.self').first();
    await marker.waitFor();
    // Friends and the current party must be visible with the general Players layer switched off.
    const otherMarkers = page.locator('.person:not(.self)');
    await page.waitForFunction(() => document.querySelectorAll('.person:not(.self)').length === 2);
    assert.equal(await otherMarkers.count(), 2, 'Game friend and party appear automatically; a public stranger stays hidden');
    await page.getByRole('tab', {name: 'Kdo mě vidí', exact: true}).click();
    await section.getByText('Přítel ze hry · ŽIVĚ', {exact: true}).waitFor();
    await section.getByText('Parta ve hře · ŽIVĚ', {exact: true}).waitFor();
    assert.equal(friendMutations, 0, 'No additional website friendship request or approval is required');
    assert.equal(await section.locator('.pp-friend').count(), 2, 'Current game relations are listed without website friendships');
    await section.locator('.pp-friend').filter({hasText: 'FriendFixture'}).getByRole('button', {name: 'Ukázat na mapě', exact: true}).click();
    await page.getByRole('tab', {name: 'Moje trasa', exact: true}).click();
    const position = await marker.evaluate(el => el.parentElement.style.transform);
    await page.waitForTimeout(6500);
    assert.notEqual(await marker.evaluate(el => el.parentElement.style.transform), position, 'Live marker must move without reload');
    await marker.hover();
    await page.getByText(/Elwynn.*ŽIVĚ/).first().waitFor();
    const output = process.env.EVERTALLY_UI_SCREENSHOT;
    if (output) await page.screenshot({path: output});
    partyPresent = false;
    await page.waitForFunction(() => document.querySelectorAll('.person:not(.self)').length === 1);
    assert.equal(await otherMarkers.count(), 1, 'Leaving the current party removes its automatic map marker');
    stale = true;
    await page.waitForTimeout(4500);
    assert.equal(await page.getByText('ŽIVĚ — poloha se aktualizuje').count(), 0, 'Expired point must lose LIVE status');
    assert.equal(await otherMarkers.count(), 0, 'Expired game-friend marker disappears');
    assert.deepEqual(errors, [], 'No uncaught browser errors');
    console.log('PASS map UI: collapse/expand, drag/persist/reset, moving live marker, automatic game friends/party with Players off, no website approval, party departure, LIVE tooltip, expiry, no JS errors');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
