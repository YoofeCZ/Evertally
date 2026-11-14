import test from "node:test";
import assert from "node:assert/strict";
import { clampDrag, MIN_VISIBLE, outOfReach, parseOffset } from "../components/evertally/db/panelDrag";

const view = { width: 1600, height: 900 };
const rect = { left: 300, top: 120, width: 340 };

test("Panel: tažení uvnitř okna posune panel přesně o tažení", () => {
  assert.deepEqual(clampDrag({ x: 0, y: 0 }, 50, 30, rect, view), { x: 50, y: 30 });
  assert.deepEqual(clampDrag({ x: 20, y: -10 }, -40, 15, rect, view), { x: -20, y: 5 }, "začíná od dosavadního posunu");
});

test("Panel: nejde ho vytáhnout z okna, aspoň kousek záhlaví zůstane vidět", () => {
  const farRight = clampDrag({ x: 0, y: 0 }, 5000, 0, rect, view);
  assert.equal(rect.left + farRight.x, view.width - MIN_VISIBLE);
  const farLeft = clampDrag({ x: 0, y: 0 }, -5000, 0, rect, view);
  assert.equal(rect.left + farLeft.x, MIN_VISIBLE - rect.width);
  const farUp = clampDrag({ x: 0, y: 0 }, 0, -5000, rect, view);
  assert.equal(rect.top + farUp.y, 0, "záhlaví nezajede nad okno");
  const farDown = clampDrag({ x: 0, y: 0 }, 0, 5000, rect, view);
  assert.ok(rect.top + farDown.y <= view.height - 44, "záhlaví nezajede pod okno");
});

test("Panel: po zmenšení okna se nedosažitelný panel pozná, viditelný ne", () => {
  const box = (left: number, top: number) => ({ left, top, right: left + 340, bottom: top + 300, width: 340 });
  assert.equal(outOfReach(box(300, 120), view), false);
  assert.equal(outOfReach(box(1580, 120), view), true, "skoro celý vpravo mimo");
  assert.equal(outOfReach(box(300, 880), view), true, "pod dolním okrajem");
  assert.equal(outOfReach({ left: 0, right: 0, top: 0, bottom: 0, width: 0 }, view), false, "skrytý panel se neřeší");
});

test("Panel: uložený posun se čte jen když je to rozumné číslo", () => {
  assert.deepEqual(parseOffset(JSON.stringify({ x: 12.4, y: -30 })), { x: 12, y: -30 });
  for (const bad of [null, "", "x", "null", "[]", JSON.stringify({ x: "1", y: 2 }), JSON.stringify({ x: 1 }), JSON.stringify({ x: 99999, y: 0 }), '{"x":1e999,"y":0}']) {
    assert.equal(parseOffset(bad), null, String(bad));
  }
});
