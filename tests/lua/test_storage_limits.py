"""The addon's local history cap must stay inside what Evertally Sync reads from Evertally.lua."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
BYTES_PER_EVENT, NODES_PER_EVENT = 715, 33   # measured 2026-11-17: 5 027 events, 3.6 MB, ~165 000 lines (upper bounds)


def const(path, name):
    """A Rust `const NAME: type = <digits, _ and *>;` as a number."""
    expr = re.search(rf"{name}: \w+ = ([\d_* ]+);", path.read_text(encoding="utf8")).group(1).replace("_", "")
    value = 1
    for factor in expr.split("*"):
        value *= int(factor)
    return value


class StorageLimitTests(unittest.TestCase):
    def test_hard_cap_fits_the_sync_apps_reader(self):
        core = (ROOT / "addon" / "Evertally" / "Core.lua").read_text(encoding="utf8")
        hard = int(re.search(r"A\.HARD_EVENTS, A\.HARD_EXPORT = (\d+)", core).group(1))
        soft = int(re.search(r"A\.MAX_EVENTS, A\.MAX_RUNS, A\.MAX_EXPORT = (\d+)", core).group(1))
        self.assertLess(soft, hard)
        local, savedvars = ROOT / "sync" / "src" / "local.rs", ROOT / "sync" / "src" / "savedvars.rs"
        self.assertLess(hard * BYTES_PER_EVENT, const(local, "MAX_HISTORY_BYTES") * 0.8)
        self.assertLess(hard * NODES_PER_EVENT, const(savedvars, "MAX_NODES_HISTORY") * 0.8)
        self.assertLess(hard, const(savedvars, "MAX_INDEX"))


if __name__ == "__main__":
    unittest.main()
