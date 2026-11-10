"""Turn Wowhead-style tooltip HTML into compact, structured rows (no HTML reaches the browser).

Row kinds (JSON arrays so shards stay small):
  ["L", spans]            a line of text; spans = [[text, cls?, itemId?], ...]
  ["C", left, right]      two columns, e.g. slot | armor type, or damage | speed
  ["M", gold, silver, copper]   sell price
  ["S"]                   a blank spacer
cls is the Wowhead colour class: q0 grey, q1 white, q2 green, q3 blue, q4 purple, q5 orange,
q6 artifact, "q" gold (headings), c1..c11 class colours, "m" muted.
"""
from __future__ import annotations

import html
import re
from html.parser import HTMLParser

VOID = {"br", "img", "hr"}


class Node:
    __slots__ = ("tag", "attrs", "children", "parent")

    def __init__(self, tag: str, attrs: dict[str, str], parent: "Node | None") -> None:
        self.tag, self.attrs, self.children, self.parent = tag, attrs, [], parent

    def classes(self) -> list[str]:
        return (self.attrs.get("class") or "").split()


class _Builder(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.root = Node("root", {}, None)
        self.cur = self.root

    def handle_starttag(self, tag, attrs):
        node = Node(tag, dict(attrs), self.cur)
        self.cur.children.append(node)
        if tag not in VOID:
            self.cur = node

    def handle_startendtag(self, tag, attrs):
        self.cur.children.append(Node(tag, dict(attrs), self.cur))

    def handle_endtag(self, tag):
        node = self.cur
        while node is not self.root and node.tag != tag:
            node = node.parent
        if node is not self.root:
            self.cur = node.parent

    def handle_data(self, data):
        self.cur.children.append(data)


def _text(node) -> str:
    if isinstance(node, str):
        return node
    return "".join(_text(c) for c in node.children if isinstance(c, str) or c.tag != "br")


class _Renderer:
    def __init__(self) -> None:
        self.rows: list[list] = []
        self.line: list[list] = []

    # --- inline ---------------------------------------------------------
    def spans(self, node, cls: str | None = None, item: int | None = None) -> list[list]:
        out: list[list] = []
        if isinstance(node, str):
            text = re.sub(r"\s+", " ", node.replace("\xa0", " "))
            if text:
                out.append((text, cls, item))
            return out
        tag = node.tag
        c = cls
        for name in node.classes():
            if re.fullmatch(r"q[0-9]?|c\d+", name):
                c = name
        it = item
        href = node.attrs.get("href") or ""
        m = re.search(r"/item=(\d+)", href)
        if tag == "a" and m:
            it = int(m.group(1))
        for child in node.children:
            out.extend(self.spans(child, c, it))
        return out

    # --- block ----------------------------------------------------------
    def flush(self) -> None:
        spans = _merge(self.line)
        self.line = []
        if spans and any(s[0].strip() for s in spans):
            spans[0] = (spans[0][0].lstrip(), *spans[0][1:])
            spans[-1] = (spans[-1][0].rstrip(), *spans[-1][1:])
            self.rows.append(["L", spans])

    def walk(self, node, cls: str | None = None, item: int | None = None) -> None:
        if isinstance(node, str):
            self.line.extend(self.spans(node, cls, item))
            return
        tag = node.tag
        classes = node.classes()
        if tag == "br":
            if not self.line and self.rows and self.rows[-1][0] != "S":
                self.rows.append(["S"])
            self.flush()
            return
        if tag == "table":
            self.table(node)
            return
        if tag == "div":
            self.flush()
            if "whtt-sellprice" in classes:
                money: dict[str, int] = {}
                for child in node.children:
                    if not isinstance(child, str):
                        for name in child.classes():
                            if name.startswith("money"):
                                money[name[5:]] = int(_text(child).strip() or 0)
                if money:
                    self.rows.append(["M", money.get("gold", 0), money.get("silver", 0), money.get("copper", 0)])
                return
            if "whtt-seasonal" in classes:
                self.rows.append(["L", _merge(self.spans(node, "m"))])
                return
            if "whtt-extra" in classes:
                return  # drop chance / dropped by are rebuilt from structured data
            if "indent" in classes:
                for child in node.children:
                    if not isinstance(child, str) and child.tag == "span":
                        self.rows.append(["L", [("  ", None, None)] + _merge(self.spans(child, "q0"))])
                return
            for child in node.children:
                self.walk(child)
            self.flush()
            return
        if tag in ("span", "b", "a", "dfn", "i", "u"):
            c, it = cls, item
            for name in classes:
                if re.fullmatch(r"q[0-9]?|c\d+", name):
                    c = name
            match = re.search(r"/item=(\d+)", node.attrs.get("href") or "")
            if tag == "a" and match:
                it = int(match.group(1))
            for child in node.children:
                self.walk(child, c, it)
            return
        for child in node.children:
            self.walk(child)

    def table(self, node) -> None:
        rows = [c for c in _descendants(node, "tr")]
        for tr in rows:
            cells = [c for c in tr.children if not isinstance(c, str) and c.tag in ("td", "th")]
            if len(cells) == 2 and cells[1].tag == "th":
                self.flush()
                self.rows.append(["C", _merge(self.spans(cells[0])), _merge(self.spans(cells[1]))])
            else:
                for cell in cells:
                    for child in cell.children:
                        self.walk(child)
                self.flush()


def _descendants(node, tag):
    # direct rows of this table only (nested tables are handled by walk)
    for child in node.children:
        if isinstance(child, str):
            continue
        if child.tag == tag:
            yield child
        elif child.tag in ("tbody", "thead"):
            yield from _descendants(child, tag)


def _merge(spans: list[tuple]) -> list[tuple]:
    out: list[tuple] = []
    for text, cls, item in spans:
        if out and out[-1][1] == cls and out[-1][2] == item:
            out[-1] = (out[-1][0] + text, cls, item)
        else:
            out.append((text, cls, item))
    return out


def _compact(spans) -> list[list]:
    """Drop trailing Nones so JSON stays small: ["x"], ["x","q2"], ["x","q2",123], ["x",null,123]."""
    out = []
    for text, cls, item in spans:
        span: list = [text, cls, item]
        while span and span[-1] is None:
            span.pop()
        out.append(span)
    return out


def parse(tooltip_html: str) -> dict:
    """Returns {rows, slot, sub} for one item tooltip."""
    builder = _Builder()
    builder.feed(tooltip_html)
    renderer = _Renderer()
    for child in builder.root.children:
        renderer.walk(child)
    renderer.flush()
    rows = renderer.rows
    # collapse repeated / edge spacers, then compact spans for JSON
    cleaned: list[list] = []
    for row in rows:
        if row[0] == "S" and (not cleaned or cleaned[-1][0] == "S"):
            continue
        cleaned.append(row)
    while cleaned and cleaned[-1][0] == "S":
        cleaned.pop()
    slot = sub = None
    for row in cleaned:
        if row[0] == "L":
            row[1] = _compact(row[1])
        elif row[0] == "C":
            row[1], row[2] = _compact(row[1]), _compact(row[2])
    for row in cleaned[:6]:
        if row[0] == "C":
            left = "".join(sp[0] for sp in row[1]).strip()
            right = "".join(sp[0] for sp in row[2]).strip()
            if left and right and not re.search(r"damage|speed", left + right, re.I):
                slot, sub = left, right
                break
    return {"rows": cleaned, "slot": slot, "sub": sub}


if __name__ == "__main__":
    import json
    import sys

    sys.stdout.reconfigure(encoding="utf-8")
    items = {i["itemId"]: i for i in json.loads(open("shared/sources/forever-items.json", encoding="utf8").read())}
    for item_id in (3041, 14154, 19019, 273044):
        result = parse(items[item_id]["tooltipHtml"])
        print("##", item_id, items[item_id]["name"], "slot", result["slot"], "/", result["sub"])
        for row in result["rows"]:
            print("  ", json.dumps(row, ensure_ascii=False)[:230])
