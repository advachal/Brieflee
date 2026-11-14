"""List the court-year-bench tars still to harvest, as a GitHub Actions matrix.

Skips shards already uploaded to the year's release, so re-running the
workflow resumes where it stopped. Prints at most --max entries.

    python tool/archive/plan.py --years 2020-2025 --courts 7_26 --repo owner/name
"""
import argparse
import json
import re
import subprocess
import urllib.parse
import urllib.request

BASE = "https://indian-high-court-judgments.s3.amazonaws.com/"
SC = "https://indian-supreme-court-judgments.s3.amazonaws.com/"


def keys(prefix: str, base: str = BASE) -> list[str]:
    out, tok = [], None
    while True:
        u = f"{base}?list-type=2&prefix={prefix}" + (f"&continuation-token={urllib.parse.quote(tok)}" if tok else "")
        x = urllib.request.urlopen(u, timeout=60).read().decode()
        out += re.findall(r"<Key>([^<]*)</Key>", x)
        m = re.search(r"<NextContinuationToken>([^<]*)<", x)
        if not m:
            return out
        tok = m.group(1)


def uploaded(repo: str, tag: str) -> set[str]:
    r = subprocess.run(["gh", "release", "view", tag, "-R", repo, "--json", "assets", "-q", ".assets[].name"],
                       capture_output=True, text=True)
    return set(r.stdout.split()) if r.returncode == 0 else set()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--years", required=True, help="e.g. 2024 or 1950-2025")
    ap.add_argument("--courts", default="all", help="comma-separated court codes (7_26 = Delhi HC, sc = Supreme Court), or all")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--max", type=int, default=250)
    a = ap.parse_args()
    lo, _, hi = a.years.partition("-")
    years = range(int(lo), int(hi or lo) + 1)
    courts = None if a.courts == "all" else set(a.courts.split(","))
    todo = []
    for y in sorted(years, reverse=True):  # recent years first
        done = uploaded(a.repo, f"archive-text-{y}")
        seen = set()
        for k in keys(f"data/tar/year={y}/"):
            m = re.match(r"data/tar/year=(\d+)/court=([^/]+)/bench=([^/]+)/", k)
            if not m or not k.endswith(".tar"):
                continue
            year, court, bench = m.groups()
            if (courts and court not in courts) or (court, bench) in seen:
                continue
            seen.add((court, bench))
            if f"text_{year}_{court}_{bench}.jsonl.gz" in done:
                continue
            todo.append({"year": year, "court": court, "bench": bench})
        # Supreme Court: English judgments only (the regional tars are translations).
        if courts is None or "sc" in courts:
            if f"text_{y}_sc_english.jsonl.gz" not in done and any(
                    k.endswith(".tar") for k in keys(f"data/tar/year={y}/english/", SC)):
                todo.append({"year": str(y), "court": "sc", "bench": "english"})
    print(json.dumps({"include": todo[: a.max]}))
    print(f"{len(todo)} shards to harvest; this run takes {min(len(todo), a.max)}", file=__import__("sys").stderr)


if __name__ == "__main__":
    main()
