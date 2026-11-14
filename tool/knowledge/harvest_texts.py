"""Fetch official judgment PDFs for a slice of the snapshot and extract text.

Reads the bundled snapshot (assets/data), selects records by subject, downloads
each PDF from the AWS Open Data mirror of the eCourts portal (CC BY 4.0),
extracts the text layer with PyMuPDF and appends one JSON line per record:
{"id", "cnr", "date", "pages", "text"}. Resumable: ids already in the output
are skipped. PDFs are deleted after extraction.

    python tool/knowledge/harvest_texts.py --out build/knowledge/texts.jsonl \
        --subjects commercial,arbitration,ip --workers 8
"""
import argparse, json, os, re, sys, tempfile, time, urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

import pymupdf

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "assets", "data")


def wanted(case_type: str, subjects: set[str]) -> bool:
    t = case_type.upper().replace(" ", "")
    if "ip" in subjects and ("IPD" in t or t == "I.P.A."):
        return True
    if "arbitration" in subjects and (t.startswith("ARB") or t.startswith("O.M.P") or t.startswith("OMP")):
        return True
    if "commercial" in subjects and "COMM" in t:
        return True
    if "all" in subjects:
        return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--subjects", default="commercial,arbitration,ip")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--snapshot", default=os.path.join(DATA, "dhc_snapshot.json"))
    a = ap.parse_args()
    subjects = set(a.subjects.split(","))
    idx = json.load(open(a.snapshot))
    meta, types = idx["meta"], idx["case_types"]
    rows = []
    for part in meta["parts"]:
        for r in json.load(open(os.path.join(DATA, part))):
            if wanted(types[r[1]], subjects):
                rows.append(r)
    done = set()
    if os.path.exists(a.out):
        for line in open(a.out):
            try:
                done.add(json.loads(line)["id"])
            except Exception:
                pass
    todo = [r for r in rows if f"{r[0]}_{r[6]}" not in done]
    if a.limit:
        todo = todo[: a.limit]
    print(f"selected={len(rows)} done={len(done)} todo={len(todo)}", file=sys.stderr, flush=True)
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="pdf_")

    def fetch(r):
        f = r[9] or meta["pdf_default"].replace("{cnr}", r[0]).replace("{date}", r[6])
        url = meta["pdf_base"] + meta["pdf_path"].replace("{src_year}", str(r[11])).replace("{file}", f)
        p = os.path.join(tmp, f)
        for attempt in range(3):
            try:
                urllib.request.urlretrieve(url, p)
                with pymupdf.open(p) as doc:
                    text = "\n".join(pg.get_text() for pg in doc)
                    pages = doc.page_count
                os.remove(p)
                return {"id": f"{r[0]}_{r[6]}", "cnr": r[0], "date": r[6], "pages": pages, "text": text}
            except Exception as e:
                err = str(e)
                time.sleep(1 + attempt * 2)
        return {"id": f"{r[0]}_{r[6]}", "cnr": r[0], "date": r[6], "pages": 0, "text": "", "error": err[:200]}

    n = 0
    t0 = time.time()
    with open(a.out, "a") as out, ThreadPoolExecutor(a.workers) as ex:
        for fut in as_completed([ex.submit(fetch, r) for r in todo]):
            out.write(json.dumps(fut.result(), ensure_ascii=False) + "\n")
            n += 1
            if n % 250 == 0:
                out.flush()
                print(f"{n}/{len(todo)} {n/(time.time()-t0):.1f}/s", file=sys.stderr, flush=True)
    print("done", n, file=sys.stderr)


if __name__ == "__main__":
    main()
