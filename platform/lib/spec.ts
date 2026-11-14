// A character's specialisation and role from its talents, the way Raider.IO shows "Restoration Druid" and filters by role.
// The specialisation is the tree with the most points. The role comes from the tree's English name when the game wrote one,
// otherwise from its place among the class's three trees (the order of the talent tabs in game). Feral druids count as
// both tank and damage, as they did in this era.
export type Role = "tank" | "healer" | "dps";
export type Spec = { index: number; name: string; points: string };

const BY_NAME: Record<string, Role[]> = {
  arms: ["dps"], fury: ["dps"], protection: ["tank"], holy: ["healer"], retribution: ["dps"], discipline: ["healer"], shadow: ["dps"],
  elemental: ["dps"], enhancement: ["dps"], restoration: ["healer"], balance: ["dps"], feralcombat: ["tank", "dps"], feral: ["tank", "dps"],
  beastmastery: ["dps"], marksmanship: ["dps"], survival: ["dps"], assassination: ["dps"], combat: ["dps"], subtlety: ["dps"],
  arcane: ["dps"], fire: ["dps"], frost: ["dps"], affliction: ["dps"], demonology: ["dps"], destruction: ["dps"],
};
// class id -> the roles of its first, second and third tree
const BY_INDEX: Record<number, Role[][]> = {
  1: [["dps"], ["dps"], ["tank"]], 2: [["healer"], ["tank"], ["dps"]], 3: [["dps"], ["dps"], ["dps"]], 4: [["dps"], ["dps"], ["dps"]],
  5: [["healer"], ["healer"], ["dps"]], 7: [["dps"], ["dps"], ["healer"]], 8: [["dps"], ["dps"], ["dps"]], 9: [["dps"], ["dps"], ["dps"]],
  11: [["dps"], ["tank", "dps"], ["healer"]],
};

/** The tree with the most points (the first one on a tie), and the points of every tree as "11/0/40". Null without any point. */
export function specOf(talents: unknown): Spec | null {
  if (!Array.isArray(talents) || !talents.length) return null;
  const trees = talents.slice(0, 4).map(t => ({ name: typeof t?.name === "string" ? t.name.trim().slice(0, 40) : "", spent: Number.isFinite(t?.spent) ? Math.max(0, Math.floor(t.spent)) : 0 }));
  let best = 0;
  trees.forEach((tree, i) => { if (tree.spent > trees[best].spent) best = i; });
  if (!trees[best].spent) return null;
  return { index: best + 1, name: trees[best].name, points: trees.map(t => t.spent).join("/") };
}

export function rolesFor(classId: number | null | undefined, spec: Pick<Spec, "index" | "name"> | null | undefined): Role[] {
  if (!spec) return [];
  const byName = BY_NAME[spec.name.toLowerCase().replace(/[^a-z]/g, "")];
  if (byName) return byName;
  return (classId != null && BY_INDEX[classId]?.[spec.index - 1]) || [];
}
