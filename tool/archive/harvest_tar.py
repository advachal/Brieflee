"""Read every judgment PDF of one court, year and bench from the Open India
Law archive (AWS Open Data: indian-high-court-judgments and, with --court sc
--bench english, indian-supreme-court-judgments; CC BY 4.0) and write
their text as one gzipped JSON-lines shard.

The archive's tar files are streamed straight from S3 and never saved, so a
4 GB court-year needs no disk beyond the output. One line per judgment:
{"file", "court", "bench", "year", "pages", "text"} (or "error").

    python tool/archive/harvest_tar.py --year 2024 --court 7_26 --bench dhcdb \
        --out text_2024_7_26_dhcdb.jsonl.gz --workers 4
"""
import argparse
import gzip
import json
import sys
import tarfile
import time
import urllib.request
from concurrent.futures import ProcessPoolExecutor

HC = "https://indian-high-court-judgments.s3.amazonaws.com/"
SC = "https://indian-supreme-court-judgments.s3.amazonaws.com/"
BASE = HC


def base_for(court: str) -> str:
    """court "sc" is the Supreme Court archive; anything else a High Court code."""
    return SC if court == "sc" else HC


def list_tars(year: str, court: str, bench: str) -> list[str]:
    import re
    prefix = f"data/tar/year={year}/{bench}/" if court == "sc" else f"data/tar/year={year}/court={court}/bench={bench}/"
    x = urllib.request.urlopen(f"{base_for(court)}?list-type=2&prefix={prefix}", timeout=60).read().decode()
    return [k for k in re.findall(r"<Key>([^<]*)</Key>", x) if k.endswith(".tar")]


def pdf_text(item):
    name, data = item
    import pymupdf
    try:
        with pymupdf.open(stream=data, filetype="pdf") as doc:
            return name, doc.page_count, "\n".join(p.get_text() for p in doc), None
    except Exception as e:  # damaged PDF: keep a record of it
        return name, 0, "", str(e)[:200]


def stream_pdfs(url: str):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=300) as r, tarfile.open(fileobj=r, mode="r|") as tar:
                for m in tar:
                    if m.isfile() and m.name.lower().endswith(".pdf"):
                        f = tar.extractfile(m)
                        if f is not None:
                            yield m.name.rsplit("/", 1)[-1], f.read()
            return
        except Exception as e:  # a dropped connection restarts the tar (rare)
            print(f"retry {attempt + 1}: {e}", file=sys.stderr, flush=True)
            time.sleep(10 * (attempt + 1))
    raise RuntimeError(f"could not read {url}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--year", required=True)
    ap.add_argument("--court", required=True)
    ap.add_argument("--bench", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--workers", type=int, default=4)
    a = ap.parse_args()

    seen: set[str] = set()
    n = errors = 0
    t0 = time.time()
    with gzip.open(a.out, "wt", encoding="utf-8", compresslevel=6) as out, ProcessPoolExecutor(a.workers) as ex:
        for key in list_tars(a.year, a.court, a.bench):
            batch = []

            def flush():
                nonlocal n, errors
                for name, pages, text, err in ex.map(pdf_text, batch, chunksize=8):
                    rec = {"file": name, "court": a.court, "bench": a.bench, "year": int(a.year), "pages": pages, "text": text}
                    if err:
                        rec["error"] = err
                        errors += 1
                    out.write(json.dumps(rec, ensure_ascii=False) + "\n")
                    n += 1
                batch.clear()
                print(f"{n} judgments, {errors} unreadable, {n / (time.time() - t0):.1f}/s", file=sys.stderr, flush=True)

            for name, data in stream_pdfs(base_for(a.court) + key):
                if name in seen:  # later part files can repeat a judgment
                    continue
                seen.add(name)
                batch.append((name, data))
                if len(batch) >= 400:
                    flush()
            if batch:
                flush()
    print(f"done: {n} judgments, {errors} unreadable, {time.time() - t0:.0f}s", file=sys.stderr)


if __name__ == "__main__":
    main()
