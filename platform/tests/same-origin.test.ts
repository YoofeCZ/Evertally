import test from "node:test";
import assert from "node:assert/strict";
import { sameOrigin } from "../lib/origin";

test("the website behind the Pi tunnel: https page, server sees plain http on the same host", () => {
  assert.equal(sameOrigin("https://evertally.afstudio.dev", "http://evertally.afstudio.dev/api/pairing"), true);
  assert.equal(sameOrigin("https://evertally.afstudio.dev", "https://evertally.afstudio.dev/api/pairing"), true);
  assert.equal(sameOrigin("http://127.0.0.1:8790", "http://127.0.0.1:8790/api/pairing"), true);
});

test("another site, a missing origin or a downgrade is refused", () => {
  assert.equal(sameOrigin(null, "http://evertally.afstudio.dev/api/pairing"), false);
  assert.equal(sameOrigin("https://evil.example", "http://evertally.afstudio.dev/api/pairing"), false);
  assert.equal(sameOrigin("https://evertally.afstudio.dev.evil.example", "http://evertally.afstudio.dev/api/pairing"), false);
  assert.equal(sameOrigin("http://evertally.afstudio.dev", "https://evertally.afstudio.dev/api/pairing"), false);
  assert.equal(sameOrigin("null", "http://evertally.afstudio.dev/api/pairing"), false);
});
