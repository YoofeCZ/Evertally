import test from "node:test";
import assert from "node:assert/strict";
import { applyPublishChoices } from "../lib/publish";
import { payloadSchemas, scopeFor } from "../lib/contracts";
import { fixture } from "./sqlite-db";

const row = (f: ReturnType<typeof fixture>, user: string) =>
  ({ ...f.sql.prepare('SELECT "public" AS p,show_item_level AS i,show_guild AS g,visibility_at AS at FROM atlas_profiles WHERE user_id=?').get(user) }) as { p: number; i: number; g: number; at: number | null };



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


test("every character is public with everything shown; a choice from the game can no longer hide it (2026-11-18)", async () => {
  const f = fixture([["a", "Ayla"]]);
  f.sql.exec(`UPDATE atlas_profiles SET "public"=1, show_item_level=1, show_guild=1, visibility_at=NULL WHERE user_id='a'`);
  assert.equal(await applyPublishChoices(f.db, "a", [{ profileId: "p-a", observedAt: 100, public: false, showItemLevel: false }]), 0);
  assert.deepEqual(row(f, "a"), { p: 1, i: 1, g: 1, at: null });
});
