"""Builds the labelling workbook (Start here, Questions, Candidates) from the gold set files."""
import json
import os
import re

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill

HERE = os.path.dirname(os.path.abspath(__file__))

qs = json.load(open(os.path.join(HERE, "goldset", "questions.json")))
cands = {c["n"]: c["candidates"] for c in json.load(open(os.path.join(HERE, "goldset", "candidates.json")))}
HEAD = PatternFill("solid", fgColor="EDEFF2")
WRAP = Alignment(wrap_text=True, vertical="top")
TOP = Alignment(vertical="top")
OUTCOME = {"petitioner": "Petitioner won", "respondent": "Respondent won", "partly": "Partly allowed",
           "settled": "Settled", "withdrawn": "Withdrawn", "remanded": "Remanded", "unclear": "Unclear", "unknown": "Not read", "infructuous": "Infructuous", "interim": "Interim order", "appointed": "Arbitrator appointed"}
ROUTE = {"simple": "Simple", "complex": "Complex", "lookup": "Lookup", "aggregate": "Count"}

wb = Workbook()
s = wb.active
s.title = "Start here"
lines = [
    ("Brieflee gold set: what to label", True),
    ("61 test questions. Your labels become the answer key that every change to Brieflee's search and answers is scored against.", False),
    ("", False),
    ("1. Candidates sheet (most of the work)", True),
    ("Each question has up to 8 judgments that today's search found. Open the PDF where the title and passage are not enough.", False),
    ("Relevance: 3 = same kind of dispute and same legal question. 2 = same legal question, different setting. 1 = same area of law only. 0 = unrelated.", False),
    ("Outcome correct?: is the outcome Brieflee read from the judgment right? Yes, No, or Unclear. Only needed where Relevance is 2 or 3; for Not read, note the real outcome if it is clear.", False),
    ("", False),
    ("2. Questions sheet", True),
    ("Missing judgments: any judgment you would expect a good search to find that is not among the candidates (case number or party names is enough).", False),
    ("Acceptable counsel: for questions about advocates, names you would accept as a sensible suggestion. Leave blank if unsure.", False),
    ("Edit the question itself if it is not how a client or lawyer would really ask; mark Status when done.", False),
    ("Count questions (58 to 61) have no candidates: just check that the question makes sense.", False),
    ("", False),
    ("About 6 to 8 hours in total. Partial labels are useful: finish whole questions rather than one column across all.", False),
]
for i, (t, bold) in enumerate(lines, 1):
    c = s.cell(row=i, column=1, value=t)
    c.alignment = Alignment(wrap_text=True, vertical="top")
    if bold:
        c.font = Font(bold=True, size=12 if i == 1 else 11)
s.column_dimensions["A"].width = 110

q = wb.create_sheet("Questions")
qh = ["#", "Question", "Type", "Practice area", "Client side", "Statutes", "Missing judgments", "Acceptable counsel", "Status", "Lawyer notes"]
q.append(qh)
for n, x in enumerate(qs, 1):
    q.append([n, x["q"], ROUTE[x["route"]], x["area"], x["side"].capitalize(), x["statutes"] or None, None, None, "To do", None])
for i, w in enumerate([5, 60, 10, 15, 12, 30, 36, 30, 12, 36], 1):
    q.column_dimensions[chr(64 + i)].width = w
for row in q.iter_rows(min_row=2):
    for c in row:
        c.alignment = WRAP
for c in q[1]:
    c.fill = HEAD
    c.font = Font(bold=True)
q.freeze_panes = "C2"

k = wb.create_sheet("Candidates")
kh = ["Q#", "Rank", "Relevance (0-3)", "Outcome correct?", "Case number", "Parties", "Decided", "Brieflee's outcome", "PDF", "Matching passage", "Question"]
k.append(kh)
for n, x in enumerate(qs, 1):
    short = x["q"] if len(x["q"]) < 120 else x["q"][:117] + "..."
    for r, c in enumerate(cands.get(n, []), 1):
        passage = re.sub(r"[\[\]]", "", c["passage"] or "")
        k.append([n, r, None, None, c["case_number"], c["title"].title(), c["date"],
                  OUTCOME.get(c["outcome"], c["outcome"]), "Open PDF", passage, short])
        cell = k.cell(row=k.max_row, column=9)
        cell.hyperlink = c["pdf_url"]
for i, w in enumerate([5, 6, 12, 13, 22, 40, 11, 15, 10, 70, 50], 1):
    k.column_dimensions[chr(64 + i)].width = w
for row in k.iter_rows(min_row=2):
    for c in row:
        c.alignment = WRAP if c.column in (6, 10, 11) else TOP
for c in k[1]:
    c.fill = HEAD
    c.font = Font(bold=True)
k.freeze_panes = "E2"
wb.save(os.path.join(HERE, "goldset", "brieflee_gold_set.xlsx"))
print(q.max_row, k.max_row)
