/** Player interaction positions are never part of an upload or public projection. */
export function worldPayload(kind: string, payload: Record<string, unknown>): Record<string, unknown> {
  const out = { ...payload };
  if (kind !== "npc.observed" || payload.positionMethod !== "unit_position") {
    delete out.x; delete out.y; delete out.z;
  }
  return out;
}
