import test from "node:test";
import assert from "node:assert/strict";
import { applyPublishChoices } from "../lib/publish";
import { payloadSchemas, scopeFor } from "../lib/contracts";
import { fixture } from "./sqlite-db";

const row = (f: ReturnType<typeof fixture>, user: string) =>
  ({ ...f.sql.prepare('SELECT "public" AS p,show_item_level AS i,show_guild AS g,visibility_at AS at FROM atlas_profiles WHERE user_id=?').get(user) }) as { p: number; i: number; g: number; at: number | null };

test("a choice from the game publishes the character and its details", async () => {
  const f = fixture([["a", "Ayla"]]);
  assert.equal(await applyPublishChoices(f.db, "a", [{ profileId: "p-a", observedAt: 100, public: true, showItemLevel: true }]), 1);
  assert.deepEqual(row(f, "a"), { p: 1, i: 1, g: 0, at: 100 });
});

test("an older game choice never undoes a newer one, from the website or the game", async () => {
  const f = fixture([["a", "Ayla"]]);
  // the website turned it on at 500 (setProfileVisibility writes visibility_at)
  f.sql.exec(`UPDATE atlas_profiles SET "public"=1, show_guild=1, visibility_at=500 WHERE user_id='a'`);
  assert.equal(await applyPublishChoices(f.db, "a", [{ profileId: "p-a", observedAt: 400, public: false }]), 0);
  assert.deepEqual(row(f, "a"), { p: 1, i: 0, g: 1, at: 500 });
  // within one upload the newest choice wins whatever the order
  await applyPublishChoices(f.db, "a", [{ profileId: "p-a", observedAt: 700, public: true, showItemLevel: true }, { profileId: "p-a", observedAt: 600, public: false }]);
  assert.deepEqual(row(f, "a"), { p: 1, i: 1, g: 1, at: 700 }, "a missing detail keeps its value");
});

test("a choice cannot touch somebody else's character", async () => {
  const f = fixture([["a", "Ayla"], ["b", "Bram"]]);
  assert.equal(await applyPublishChoices(f.db, "a", [{ profileId: "p-b", observedAt: 100, public: true }]), 0);
  assert.equal(row(f, "b").p, 0);
});

test("the event is a character choice: own_character scope and a strict payload", () => {
  assert.equal(scopeFor("character.publish"), "own_character");
  assert.equal(payloadSchemas["character.publish"].safeParse({ public: true, showGuild: false }).success, true);
  assert.equal(payloadSchemas["character.publish"].safeParse({ public: "yes" }).success, false);
  assert.equal(payloadSchemas["character.publish"].safeParse({ public: true, gear: [] }).success, false);
});

test("two choices in the same second both apply, the later one last", async () => {
  const f = fixture([["a", "Ayla"]]);
  await applyPublishChoices(f.db, "a", [{ profileId: "p-a", observedAt: 100, public: true }, { profileId: "p-a", observedAt: 100, public: true, showItemLevel: true }]);
  assert.deepEqual(row(f, "a"), { p: 1, i: 1, g: 0, at: 100 });
});
