# Evaluation

Scores Brieflee's search and answers against a gold set labelled by a lawyer, stage by stage, so a drop can be traced to the stage that caused it.

| File | What it is |
| --- | --- |
| `goldset/questions.json` | 61 test questions with their expected route, practice area, side and statutes |
| `goldset/candidates.json` | Up to 8 judgments per question, pooled from keyword search, for the lawyer to grade 0 to 3 |
| `goldset/labels.json` | The lawyer's grades, missing judgments, acceptable counsel and outcome checks (made by `labels_from_sheet.py`) |
| `pool_candidates.py` | Rebuilds `candidates.json` from a knowledge database |
| `make_sheet.py` | Builds the labelling workbook from the two files above |
| `labels_from_sheet.py` | Turns CSV exports of the labelled sheet into `labels.json` |
| `run_eval.py` | Route accuracy; recall@10, recall@30, MRR, nDCG@10; answer-gate pass rate; outcome accuracy |

```
python tool/eval/run_eval.py                              # route accuracy only (also runs in CI)
python tool/eval/run_eval.py --db knowledge.db            # search alone, no AI
python tool/eval/run_eval.py --url http://localhost:8000  # the whole service, with AI steps and the answer gate
```

The "Evaluate search" workflow runs the search-only score on GitHub Actions with the published database.

Candidates come from one search method, so judgments that method never finds can only enter the gold set through the lawyer's "Missing judgments" column. `unjudged@10` counts top-10 results that nobody graded: when it is high, label more before trusting the score.

## Baseline, 15 Nov 2026 (search only, no AI)

Labels: 456 candidate judgments graded across 57 questions, plus missing judgments named by the lawyer (47 found in the database, 110 not in it, mostly Supreme Court rulings before 2015 or other courts). Result file: `results/2026-11-15-search-only.json`.

| Measure | Score |
| --- | --- |
| Route accuracy | 0.98 (60 of 61) |
| Recall@10 | 0.65 (simple 0.66, complex 0.56) |
| Recall@30 | 0.80 |
| MRR | 0.82 |
| nDCG@10 | 0.62 |
| Unjudged in top 10 | 4.7 of 10 |
| Outcome reading correct | 11 of 12 checked |

Read with care: the candidates came from this same keyword search, so the scores flatter it, and about half of each top 10 was never graded. Weakest questions: 30 (CRPF/BSF dismissal, nothing relevant found), 43, 44 and 46 (complex), 5 (Perkins Eastman), 20 (HUF partition).
