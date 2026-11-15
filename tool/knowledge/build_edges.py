"""Builds the citation and appeal graph inside knowledge.db: one `edges` table.

    python tool/knowledge/build_edges.py knowledge.db            # whole database
    python tool/knowledge/build_edges.py knowledge.db --sample 500   # measure only, writes nothing

Edges (src → dst, both record ids):
  cites      the src judgment refers to the dst judgment, found by
             - a case number written in the text ("W.P.(C) 1033/2025",
               "Civil Appeal No. 4832 of 2022") that is the case number of a record,
             - a Supreme Court Reports citation ("[2022] 13 S.C.R. 1064", "(2022) 13 SCR 1064"),
               which is how the Supreme Court records are keyed,
             - a case name followed by a report citation ("X v. Y, (2019) 5 SCC 123"),
               matched to one Supreme Court record with both parties and the year (±1).
  appeal_of  the src is an appeal (LPA, FAO, RFA, CRL.A, Supreme Court appeals …)
             and the dst is the earlier Delhi High Court decision it names next to
             words like "impugned", "assailed", "against the judgment", "arising out of".

A batch of connected matters decided together is not a citation: mentions of a
record decided on the same day as src are skipped. Each edge keeps the words
it was read from (`evidence`), so it can be checked. Nothing here calls a model.
"""
import argparse
import json
import random
import re
import sqlite3
import sys
import time
from collections import Counter, defaultdict

CASE_NO = re.compile(
    r"\b((?:[A-Z][A-Za-z]*\.?\s?){1,4}(?:\((?:[A-Za-z]+\.?\s?){1,3}\))?(?:\s?[A-Z]+\.?)?)\s*(?:No\.?\s*)?(\d{1,6})\s*/\s*((?:19|20)\d{2})\b")
CASE_NO_OF = re.compile(
    r"\b((?:Civil|Criminal|Writ|Special Leave|Transfer)\s+(?:Appeal|Petition|Leave Petition)(?:\s*\((?:C|Crl|Civil|Criminal)\.?\))?|(?:Anticipatory\s+)?Bail\s+Appl(?:ication|n)\.?)\s*(?:Nos?\.?\s*)?(\d{1,6})\s+of\s+((?:19|20)\d{2})",
    re.I)
SCR = re.compile(r"[\[(]((?:19|20)\d{2})[\])]\s*(\d{1,2})\s*S\.?\s?C\.?\s?R\.?\s*(\d{1,5})")
SCC_NAMED = re.compile(
    r"([A-Z][\w.&'@ ]{2,80}?)\s+(?:v\.?|vs\.?|versus)\s+([A-Z][\w.&'@ ()]{2,80}?)\s*[,(\[]\s*\(?((?:19|20)\d{2})\)?\s*\d*\s*(?:SCC|S\.C\.C\.|SCR|S\.C\.R\.|AIR|SCC OnLine)")
APPEAL_TYPES = tuple(re.sub(r"[^A-Z0-9]", "", t) for t in ("LPA", "FAO", "RFA", "CRL.A", "CRL.REV", "MAT.APP", "EFA", "CIVILAPPEAL", "CRIMINALAPPEAL", "SLP"))
# ITA (income-tax appeals) come from the tribunal, which is not in the database,
# and an appeal does not lie from a matter of its own type (LPA → LPA is a sibling).
APPEAL_WORDS = re.compile(r"impugn|assail|against the (?:judgment|order)|arising out of|appeal (?:is )?(?:directed|preferred|filed) against|"
                          r"set(?:ting)? aside the (?:judgment|order)|(?:is|are|stands) (?:hereby )?set aside|challeng\w* the (?:judgment|order)", re.I)
SKIP = {"M/S", "MS", "THE", "AND", "ANR", "ORS", "LTD", "LIMITED", "PVT", "PRIVATE", "CO", "OF", "&", "STATE", "UNION", "INDIA"}


ALIASES = [(r"^WRITPETITION(?:CIVIL|C)", "WPC"), (r"^WRITPETITION(?:CRIMINAL|CRL)", "WPCRL"), (r"^CRLA$", "CRLA"), (r"^(?:ANTICIPATORY)?BAILAPPLICATION$", "BAILAPPLN")]


def norm(s: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", (s or "").upper())


def norm_type(s: str) -> str:
    """A case type as written in text, in the form the records use: no "No."
    and no stray word before it ("Laws. FAO(OS)"), long names shortened."""
    t = re.sub(r"\bNOS?\.?\s*$", "", (s or "").upper().strip())
    t = norm(t)
    for rx, rep in ALIASES:
        t = re.sub(rx, rep, t)
    return t


def toks(name: str) -> set[str]:
    return {t for t in re.findall(r"[A-Z0-9]+", name.upper()) if t not in SKIP and len(t) > 2}


class Index:
    def __init__(self, db: sqlite3.Connection):
        self.by_no: dict[str, list[tuple]] = defaultdict(list)
        self.by_scr: dict[str, str] = {}
        self.sc_by_year: dict[int, list[tuple]] = defaultdict(list)
        self.meta: dict[str, tuple] = {}
        for rid, cn, ct, date, court, p, r in db.execute(
                "SELECT id, case_number, case_type, decision_date, court, petitioner, respondent FROM records"):
            self.meta[rid] = (cn, ct, date or "", court)
            if cn:
                key = norm(cn)
                self.by_no[key].append((rid, date or "", court))
                tail = re.search(r"(\d{1,6})/((?:19|20)\d{2})$", cn.replace(" ", ""))
                if tail:  # "CIVIL APPEAL 4832/2022" also as "CIVILAPPEAL48322022"-style keys for "No. X of Y"
                    self.by_no[norm(ct or "")[:6] + "#" + tail.group(1) + "/" + tail.group(2)].append((rid, date or "", court))
            m = re.match(r"SC_(\d{4})_(\d+)_(\d+)_(\d+)", rid)
            if m:
                y, vol, p0, p1 = map(int, m.groups())
                for page in range(p0, p1 + 1):
                    self.by_scr.setdefault(f"{y}/{vol}/{page}", rid)
                self.sc_by_year[y].append((rid, toks(p or ""), toks(r or "")))

    def case_number(self, ctype: str, num: str, year: str) -> list[tuple]:
        t = norm_type(ctype)
        hits = self.by_no.get(t + norm(f"{num}/{year}"), [])
        if not hits and len(t) > 3:  # a word glued in front: "LawsFAOOS" → try its tail
            for k in range(1, min(8, len(t) - 2)):
                hits = self.by_no.get(t[k:] + norm(f"{num}/{year}"), [])
                if hits:
                    break
        if not hits:
            hits = self.by_no.get(norm(ctype)[:6] + "#" + f"{num}/{year}", [])
        return hits

    def named_sc(self, a: str, b: str, year: int) -> str | None:
        ta, tb = toks(a), toks(b)
        if not ta or not tb:
            return None
        found = {rid for y in (year - 1, year, year + 1) for rid, p, r in self.sc_by_year.get(y, [])
                 if (ta <= p and tb <= r) or (ta <= r and tb <= p)}
        return found.pop() if len(found) == 1 else None


def edges_for(rid: str, text: str, idx: Index) -> list[tuple]:
    own_no, own_type, own_date, own_court = idx.meta[rid]
    own = norm(own_no)
    out: dict[tuple, str] = {}

    def add(dst, kind, ev):
        if dst and dst != rid and (dst, kind) not in out:
            out[(dst, kind)] = " ".join(ev.split())[:200]

    is_appeal = norm(own_type).startswith(APPEAL_TYPES) or norm(own_no).startswith(APPEAL_TYPES)
    own_scr = re.match(r"SC_(\d{4})_(\d+)_", rid)
    spans = [m.start() for m in CASE_NO.finditer(text)]
    for rx in (CASE_NO, CASE_NO_OF):
        for m in rx.finditer(text):
            if norm_type(m.group(1)) + norm(f"{m.group(2)}/{m.group(3)}") == own:
                continue
            if sum(1 for x in spans if abs(x - m.start()) < 160) >= 4:
                continue  # a list of connected matters, not a citation
            for dst, date, court in idx.case_number(m.group(1), m.group(2), m.group(3)):
                if date == own_date or (date and own_date and date > own_date):
                    continue  # same batch, or a later decision with the same number
                around = text[max(0, m.start() - 250): m.end() + 80]
                same_type = re.match(r"[A-Z]+", norm(idx.meta[dst][0]) or "x").group(0) == re.match(r"[A-Z]+", own or "y").group(0)
                kind = "appeal_of" if is_appeal and not same_type and court == "7_26" and APPEAL_WORDS.search(around) else "cites"
                add(dst, kind, around[200:] if len(around) > 280 else around)
    for m in SCR.finditer(text):
        if own_scr and (m.group(1), str(int(m.group(2)))) == (own_scr.group(1), own_scr.group(2)):
            continue  # the report's own running heads and index of the same volume
        dst = idx.by_scr.get(f"{int(m.group(1))}/{int(m.group(2))}/{int(m.group(3))}")
        add(dst, "cites", m.group(0))
    for m in SCC_NAMED.finditer(text):
        dst = idx.named_sc(m.group(1)[-60:], m.group(2), int(m.group(3)))
        add(dst, "cites", m.group(0))
    return [(rid, dst, kind, ev) for (dst, kind), ev in out.items()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("db")
    ap.add_argument("--sample", type=int, default=0)
    ap.add_argument("--appeals", action="store_true", help="sample appeal-type records only")
    a = ap.parse_args()
    db = sqlite3.connect(a.db)
    t0 = time.time()
    idx = Index(db)
    print(f"index: {len(idx.meta)} records, {len(idx.by_scr)} SCR pages, {time.time() - t0:.0f}s", flush=True)
    ids = list(idx.meta)
    if a.sample:
        random.seed(7)
        pool = ids if not a.appeals else [r for r in ids if norm(idx.meta[r][1]).startswith(APPEAL_TYPES)]
        ids = random.sample(pool, a.sample)
    else:
        db.executescript("""DROP TABLE IF EXISTS edges;
            CREATE TABLE edges(src TEXT, dst TEXT, kind TEXT, evidence TEXT);""")
    stats, made, batch = Counter(), [], []
    for n, rid in enumerate(ids, 1):
        text = " ".join(r[0] for r in db.execute("SELECT text FROM chunks WHERE record_id = ? ORDER BY chunk_index", (rid,)))
        e = edges_for(rid, text, idx)
        stats["records"] += 1
        stats["with_cites"] += any(k == "cites" for _, _, k, _ in e)
        stats["with_appeal_of"] += any(k == "appeal_of" for _, _, k, _ in e)
        for _, _, k, _ in e:
            stats[k] += 1
        stats["mentions_scc_air"] += len(re.findall(r"SCC|AIR\s*\d{4}|S\.C\.R|SCR", text))
        if a.sample:
            made.extend(e)
        else:
            batch.extend(e)
            if len(batch) > 20000:
                db.executemany("INSERT INTO edges VALUES (?,?,?,?)", batch)
                batch = []
        if n % 20000 == 0:
            print(n, dict(stats), f"{time.time() - t0:.0f}s", flush=True)
    if not a.sample:
        db.executemany("INSERT INTO edges VALUES (?,?,?,?)", batch)
        db.executescript("""CREATE INDEX ix_edges_src ON edges(src, kind);
            CREATE INDEX ix_edges_dst ON edges(dst, kind);""")
        db.commit()
    print(json.dumps(dict(stats)), f"{time.time() - t0:.0f}s")
    if a.sample:
        random.shuffle(made)
        for s, d, k, ev in made[:25]:
            print(k, s, "->", d, idx.meta[d][0], "|", ev[:140])


if __name__ == "__main__":
    sys.exit(main())
