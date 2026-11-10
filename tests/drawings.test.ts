import test from "node:test";
import assert from "node:assert/strict";
import { sanitizeDrawings } from "../components/evertally/db/draw";

test("Kresby z první verze bez tloušťky a zoomu dostanou rozumné výchozí hodnoty", () => {
  const [arrow] = sanitizeDrawings([{ kind: "arrow", color: "#ffd24a", points: [[0.1, 0.2], [0.3, 0.4]] }]);
  assert.equal(arrow.width, 4);
  assert.equal(arrow.zoom, 2);
  assert.ok(Number.isFinite(arrow.width) && Number.isFinite(arrow.zoom));
  assert.match(arrow.id, /^legacy-/);
});
test("Platná kresba zůstane beze změny", () => {
  const good = { id: "a", kind: "circle" as const, color: "#ff0000", width: 6, zoom: 3.5, points: [[0.1, 0.1], [0.2, 0.2]] as [number, number][] };
  assert.deepEqual(sanitizeDrawings([good]), [good]);
});
test("Poškozené záznamy se zahodí, ostatní přežijí", () => {
  const out = sanitizeDrawings([null, 5, { kind: "spray", points: [[0, 0], [1, 1]] }, { kind: "line", points: [[0, 0]] }, { kind: "line", points: [[null, 0], [1, 1]] },
    { kind: "mark", points: [[0.5, 0.5]] }, { kind: "free", color: "javascript:alert(1)", width: -3, zoom: Infinity, points: [[0, 0], [1, 1], [NaN, 2]] }]);
  assert.deepEqual(out.map(d => d.kind), ["mark", "free"]);
  assert.equal(out[1].color, "#ffd24a");
  assert.equal(out[1].width, 4);
  assert.equal(out[1].points.length, 2);
});
test("Co není pole, nejsou kresby", () => {
  assert.deepEqual(sanitizeDrawings(null), []);
  assert.deepEqual(sanitizeDrawings({ kind: "line" }), []);
});
