"""Czech for the guide texts that repeat one shape (tools/polestar-cs/texts.json), by rule.

    python -I tools/polestar_cs_rules.py

Many guide texts differ only in their numbers and tokens ({npc:123}, {zone:1411}): "11 areas to discover here, levels
5-10." These rules translate such a shape once. A rule fills only texts not translated yet, and its result must keep
the English's placeholders (tools/polestar_cs_batch.py keep_marks), else it is left out.
"""
from __future__ import annotations

import importlib.util
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("batch", ROOT / "tools" / "polestar_cs_batch.py")
batch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(batch)

T = r"(\{\w+:\d+\})"          # one token
N = r"(\d[\d,.]*)"            # one number
RULES: list[tuple[str, str]] = [
    (rf"^{T}: kill these as you meet them$", r"\1: zabíjej je, jak na ně narazíš"),
    (rf"^The {T}$", r"\1"),
    (rf"^{T} to {N}$", r"\1 na \2"),
    (rf"^{T}, inside$", r"\1, uvnitř"),
    (rf"^Back to {T}$", r"Zpět do \1"),
    (rf"^{T}, {N}g$", r"\1, \2g"),
    (rf"^{T}, from {T}$", r"\1, od \2"),
    (rf"^{T}, {N} reputation$", r"\1, \2 reputace"),
    (rf"^Fly to {T}$", r"Leť do \1"),
    (rf"^{T} takes it once your {T} skill is {N}: gather or craft until then, the guide carries on meanwhile\.$",
     r"\1 ho vezme, až budeš mít dovednost \2 na \3: do té doby sbírej nebo vyráběj, návod mezitím pokračuje."),
    (rf"^{T} flight master$", r"letový mistr \1"),
    (rf"^grind on {T}$", r"grinduj na \1"),
    (rf"^Level {N}$", r"Level \1"),
    (rf"^{T} recipes at {N}$", r"recepty \1 na \2"),
    (r"^(\d+) areas? to discover here, levels? (\d+)-(\d+)\.?$", r"Oblastí k objevení: \1, levely \2–\3."),
    (rf"^{T}, below ground$", r"\1, pod zemí"),
    (rf"^{T} and {T}$", r"\1 a \2"),
    (rf"^{T} \(Alliance\)$", r"\1 (Aliance)"),
    (rf"^{T}, upstairs$", r"\1, nahoře"),
    (rf"^{T} \(Horde\)$", r"\1 (Horda)"),
    (rf"^What {T} takes that the Auction House sells: {N} {T}\. The counts drop by what your bags, bank and mail hold\.$",
     r"Co \1 potřebuje a aukce prodává: \2 \3. Počty se sníží o to, co máš v taškách, bance a poště."),
    (rf"^{T}: for {T}$", r"\1: pro \2"),
    (rf"^{T}: {T}'s letter$", r"\1: dopis od \2"),
    (rf"^{T} {N}-{N}: Auction House$", r"\1 \2–\3: aukce"),
    (rf"^{N} {T} for {T}: {T}: {T} \(skill {N}\)\. The densest cluster of {T} in {T} is marked\.$",
     r"\1 \2 pro \3: \4: \5 (dovednost \6). Nejhustší výskyt \7 v \8 je označený."),
    (rf"^Beasts {N}-{N}: {T} \({N}-{N}\)$", r"Zvířata \1–\2: \3 (\4–\5)"),
    (rf"^{T} in {T}$", r"\1 v \2"),
    (rf"^{T}: Auction House$", r"\1: aukce"),
    (rf"^{T}; below ground$", r"\1; pod zemí"),
    (rf"^{T}, beside {T}$", r"\1, vedle \2"),
    (rf"^{T} walks around {T}: look inside the circle on the map$", r"\1 chodí po \2: hledej uvnitř kruhu na mapě"),
    (rf"^Flight path here: {T} \({T}\)\.$", r"Letová trasa tady: \1 (\2)."),
    (rf"^{T} {N}-{N}: vendor goods$", r"\1 \2–\3: zboží od obchodníků"),
    (rf"^Into {T}$", r"Do \1"),
    (rf"^{T} to Revered$", r"\1 na Revered"),
    (rf"^{T}, Friendly$", r"\1, Friendly"),
    (rf"^Horde guards: touch the edge of {T} and move on$", r"Stráže Hordy: dotkni se okraje \1 a jdi dál"),
    (rf"^Alliance guards: touch the edge of {T} and move on$", r"Stráže Aliance: dotkni se okraje \1 a jdi dál"),
    (rf"^{T}: the {T}$", r"\1: \2"),
    (rf"^{T}, {N}s$", r"\1, \2s"),
    (rf"^{T} sells the other colours \({N}g each in the Forever client\)\. Buy any you want, or none if the mount you were given is the one you like\.$",
     r"\1 prodává ostatní barvy (ve klientu Forever po \2g). Kup si, kterou chceš, nebo žádnou, pokud se ti líbí mount, který jsi dostal."),
    (rf"^{T} to Honored$", r"\1 na Honored"),
    (rf"^{T} to Exalted$", r"\1 na Exalted"),
    (rf"^{T}: take her {T} letter$", r"\1: vezmi její dopis \2"),
    (rf"^{T}: take his {T} letter$", r"\1: vezmi jeho dopis \2"),
    (rf"^{T}: for {T} in {T}$", r"\1: pro \2 v \3"),
    (rf"^{T}: ingredients$", r"\1: suroviny"),
    (rf"^{T}, from the {T}$", r"\1, od \2"),
    (rf"^Journeyman {T}$", r"Journeyman \1"),
    (rf"^To {T}$", r"Do \1"),
    (rf"^{T}: hand in$", r"\1: odevzdej"),
    (rf"^{T}; underwater$", r"\1; pod vodou"),
    (rf"^{N} {T} for {T} and {T} \({N} of them for {N}-{N}: pick them all now\): {T}: {T} \(skill {N}\)\. The densest patch of {T} in {T} is marked\.$",
     r"\1 \2 pro \3 a \4 (\5 z nich pro \6–\7: natrhej je všechny teď): \8: \9 (dovednost \10). Nejhustší porost \11 v \12 je označený."),
    (rf"^{N} {T} for {T}: {T}: {T} \(skill {N}\) in {T} \({N}-{N}\), {T} \({N}-{N}\) and {T} \({N}-{N}\)\. The densest cluster of {T} in {T} is marked\.$",
     r"\1 \2 pro \3: \4: \5 (dovednost \6) v \7 (\8–\9), \10 (\11–\12) a \13 (\14–\15). Nejhustší výskyt \16 v \17 je označený."),
    (rf"^Artisan {T}$", r"Artisan \1"),
    (rf"^Expert {T}$", r"Expert \1"),
    (rf"^Learn {T}$", r"Nauč se \1"),
    (rf"^{T}: shopping$", r"\1: nákupy"),
    (rf"^{T}, Honored$", r"\1, Honored"),
    (rf"^{T}: {T} and your {T}$", r"\1: \2 a tvůj \3"),
    (rf"^{N} {T} for {T}: {T}: smelt {T}\.$", r"\1 \2 pro \3: \4: přetav \5."),
    (rf"^{N} {T} for {T} and {T}: {T}: smelt {T}\.$", r"\1 \2 pro \3 a \4: \5: přetav \6."),
    (rf"^{N} {T} for {T}: {T}: {T}\.$", r"\1 \2 pro \3: \4: \5."),
    (rf"^{N} {T} for {T}: {T}: disenchant green items of item level {N}-{N}\.$",
     r"\1 \2 pro \3: \4: disenchantuj zelené předměty item levelu \5–\6."),
    (rf"^{N} {T} for {T} and {T}: {T}: disenchant green items of item level {N}-{N}\.$",
     r"\1 \2 pro \3 a \4: \5: disenchantuj zelené předměty item levelu \6–\7."),
    (rf"^{N} {T} for {T}: humanoids of level {N}-{N} drop it\. Keep what you loot as you level, or take it from your bank\.$",
     r"\1 \2 pro \3: dropují ho humanoidi levelu \4–\5. Nech si, co nalootuješ při levelování, nebo si ho vezmi z banky."),
    (rf"^{N} {T} for {T}: {T}: {T} \(skill {N}\)\. The densest cluster of {T} in {T} is marked\.$",
     r"\1 \2 pro \3: \4: \5 (dovednost \6). Nejhustší výskyt \7 v \8 je označený."),
    (rf"^{N} {T} for {T}: it drops from {T} \(level {N}-{N}\) at the marked spot\.$",
     r"\1 \2 pro \3: dropuje z \4 (level \5–\6) na označeném místě."),
]
SKIN = re.compile(rf"^{N} {T} for (.+?): {T}: beasts of level {N}-{N}\. Skin (.+?) here \(level {N}-{N}\); the {T} guide routes this\.$")
MINE = re.compile(rf"^{N} {T} for (.+?): {T} turns up in about one (.+?) in {N}: keep the ones you find while mining\.$")


def fors(s: str) -> str:
    return s.replace(" and ", " a ")


def apply(en: str) -> str | None:
    for pat, rep in RULES:
        m = re.match(pat, en)
        if m:
            return m.expand(rep)
    m = SKIN.match(en)
    if m:
        n, item, what, skill, lo, hi, mobs, lo2, hi2, skill2 = m.groups()
        return (f"{n} {item} pro {fors(what)}: {skill}: zvířata levelu {lo}–{hi}. Stahuj {fors(mobs)} tady "
                f"(level {lo2}–{hi2}); trasu vede návod na {skill2}.")
    m = MINE.match(en)
    if m:
        n, item, what, tok, objs, per = m.groups()
        return f"{n} {item} pro {fors(what)}: {tok} se objeví zhruba v jednom z {per} {fors(objs).replace(' or ', ' nebo ')}: nech si, co najdeš při těžbě."
    return None


def main() -> None:
    path = ROOT / "tools" / "polestar-cs" / "texts.json"
    memory = json.loads(path.read_text(encoding="utf8"))
    done = refused = 0
    for en, cs in memory.items():
        if cs:
            continue
        out = apply(en)
        if out is None:
            continue
        if batch.keep_marks(en, out):
            memory[en] = out
            done += 1
        else:
            refused += 1
    path.write_text(json.dumps(dict(sorted(memory.items())), ensure_ascii=False, indent=0) + "\n", encoding="utf8")
    print(f"by rule: {done} translated, {refused} refused")


if __name__ == "__main__":
    main()
