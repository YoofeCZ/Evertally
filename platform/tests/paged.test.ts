import test from "node:test";
import assert from "node:assert/strict";
import { pageNumbers } from "../components/evertally/Paged";

test("short lists show every page number", () => {
  assert.deepEqual(pageNumbers(0, 1), [0]);
  assert.deepEqual(pageNumbers(3, 7), [0, 1, 2, 3, 4, 5, 6]);
});

test("long lists keep the first, the last and the neighbours of the current page", () => {
  assert.deepEqual(pageNumbers(0, 20), [0, 1, null, 19]);
  assert.deepEqual(pageNumbers(10, 20), [0, null, 9, 10, 11, null, 19]);
  assert.deepEqual(pageNumbers(19, 20), [0, null, 18, 19]);
  assert.deepEqual(pageNumbers(2, 20), [0, 1, 2, 3, null, 19]);
});
