"""Split the untranslated guide texts (tools/polestar-cs/texts.json) among several translators working at once.

    python -I tools/polestar_cs_parallel.py split 10 60     # 10 chunks, parts of at most 60 strings
    python -I tools/polestar_cs_parallel.py check 03        # checks chunk 03's finished parts, lists the missing ones
    python -I tools/polestar_cs_parallel.py merge           # stores every good translation in texts.json

split writes tools/polestar-cs/batch/parallel/cNN_pMM.in.json ([[number, english], ...]). A translator writes
cNN_pMM.out.json next to it: a JSON list of the Czech strings in the same order. Translators never touch texts.json;
merge does that, with the same placeholder check as tools/polestar_cs_batch.py.
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("batch", ROOT / "tools" / "polestar_cs_batch.py")
batch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(batch)
PAR = batch.BATCH / "parallel"


def parts(chunk: str = "*"):
    return sorted(PAR.glob(f"c{chunk}_p*.in.json"))


def check_part(inp: Path):
    out = inp.with_name(inp.name.replace(".in.", ".out."))
    if not out.exists():
        return None, []
    todo = json.loads(inp.read_text(encoding="utf8"))
    try:
        got = json.loads(out.read_text(encoding="utf8"))
    except json.JSONDecodeError as e:
        return False, [f"invalid JSON: {e}"]
    if not isinstance(got, list) or len(got) != len(todo):
        return False, [f"{len(got) if isinstance(got, list) else '?'} translations for {len(todo)} strings"]
    bad = [f"#{i}: placeholders differ: {en[:80]!r}" for (i, en), cs in zip(todo, got)
           if cs and not batch.keep_marks(en, cs)]
    return not bad, bad


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "split":
        n, size = int(sys.argv[2]), int(sys.argv[3])
        PAR.mkdir(parents=True, exist_ok=True)
        for old in PAR.glob("*.in.json"):
            old.unlink()
        todo = [k for k, v in batch.load("texts").items() if not v]
        total = sum(len(k) for k in todo)
        chunks, cur, acc = [[] for _ in range(n)], 0, 0
        for k in todo:  # contiguous chunks of about equal characters
            if acc >= total * (cur + 1) / n and cur < n - 1:
                cur += 1
            chunks[cur].append(k)
            acc += len(k)
        for ci, ch in enumerate(chunks, 1):
            for pi in range(0, len(ch), size):
                part = ch[pi:pi + size]
                f = PAR / f"c{ci:02d}_p{pi // size + 1:02d}.in.json"
                f.write_text(json.dumps([[i, k] for i, k in enumerate(part)], ensure_ascii=False, indent=0) + "\n",
                             encoding="utf8")
            print(f"chunk {ci:02d}: {len(ch)} strings, {sum(map(len, ch))} characters, {len(parts(f'{ci:02d}'))} parts")
    elif cmd == "check":
        missing = []
        for inp in parts(sys.argv[2]):
            ok, errs = check_part(inp)
            if ok is None:
                missing.append(inp.name)
            elif not ok:
                print(f"{inp.name}: BAD"); [print("   ", e) for e in errs]
        print(f"missing: {', '.join(missing) if missing else 'none'}")
    elif cmd == "merge":
        m = batch.load("texts")
        good = bad = 0
        for inp in parts():
            ok, _ = check_part(inp)
            if ok is None:
                continue
            todo = json.loads(inp.read_text(encoding="utf8"))
            got = json.loads(inp.with_name(inp.name.replace(".in.", ".out.")).read_text(encoding="utf8"))
            if len(got) != len(todo):
                bad += len(todo); continue
            for (i, en), cs in zip(todo, got):
                if cs and batch.keep_marks(en, cs):
                    m[en] = cs; good += 1
                elif cs:
                    bad += 1
        batch.save("texts", m)
        print(f"merged {good}, refused {bad}")
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
